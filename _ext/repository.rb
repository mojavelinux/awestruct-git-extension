require 'rubygems'
require 'ostruct'
require 'uri'
require 'rest-client'
require 'json'
require 'rexml/document'

module Awestruct
  module Extensions
    module Repository
      # TODO make collectors modular, so that we register an ohloh collector for instance
      class Collector
        def initialize(ohloh_project_id, ohloh_api_key)
          @repositories = []
          @ohloh_project_id = ohloh_project_id
          @ohloh_api_key = ohloh_api_key
        end

        def execute(site)

          more_pages = true
          page = 1
          while more_pages do
            cache_file = File.join(site.tmp_dir, "ohloh-enlistments-#{@ohloh_project_id}-#{page}.xml")
            if !File.exist? cache_file
              url = "http://www.ohloh.net/p/#{@ohloh_project_id}/enlistments.xml?page=#{page}&api_key=#{@ohloh_api_key}"
              puts "Fetching #{url}"
              response_body = RestClient.get(url) { |response, request, result, &block|
                case response.code
                  when 404
                    response
                  else
                    response.return!(request, result, &block)
                end
              }.body;
              File.open(cache_file, 'w').write response_body
            else
              response_body = File.read(cache_file)
            end

            doc = REXML::Document.new(response_body)
            doc.each_element('/response/result/enlistment/repository/url') do |e|
              git_url = e.text  
              path = File.basename(git_url.split('/').last, '.git')
              @repositories << OpenStruct.new({
                :path => path,
                :desc => nil,
                :owner => git_url.split('/').last(2).first,
                :host => URI(git_url).host,
                :type => 'git',
                :http_url => git_url.chomp('.git').sub('git://', 'http://'),
                :clone_url => git_url
              })
            end

            offset = doc.root.elements['first_item_position'].text.to_i
            returned = doc.root.elements['items_returned'].text.to_i
            available = doc.root.elements['items_available'].text.to_i
            
            if offset + returned < available
              page += 1
            else
              more_pages = false
            end
          end

          @repositories.sort! {|a,b| a.path <=> b.path }
          @repositories.map {|r|
            r.owner if r.host == 'github.com'
          }.uniq.each {|org_name|
            cache_file = File.join(site.tmp_dir, "github-org-repos-#{org_name}.xml")
            if !File.exist? cache_file
              url = "https://api.github.com/orgs/#{org_name}/repos" 
              puts "Fetching #{url}" 
              response_body = RestClient.get(url) { |response, request, result, &block|
                case response.code
                  when 404
                    response
                  else
                    response.return!(request, result, &block)
                end
              }.body;
              File.open(cache_file, 'w').write response_body
            else
              response_body = File.read(cache_file) 
            end
            org_repos_data = JSON.parse response_body  
            @repositories.each {|r|
              repo_data = org_repos_data.select {|c| r.owner == org_name and r.host == 'github.com' and c['name'] == r.name}
              if repo_data.size == 1
                r.desc = repo_data.first['description']
              end
            }
          }

          @repositories.each do |r|
            Visitors.defined.each_value do |v|
              if v.handles(r)
                v.visit(r, site)
              end
            end
          end
        end
      end

      module Visitors
        # @return [{String => Repository::Visitors::Base}] a hash of visitor names to classes
        def self.defined
          @defined ||= {}
        end

        module Base
          def self.included(base)
            Visitors.defined[base.name.split('::').last.downcase] = base
            base.extend(base)
          end

          def handles(repository)
            true
          end

          # TODO could allow return false to halt processing of visitors
          def visit(repository, site)
            raise Error.new("#{self.inspect}#visit not defined!")
          end
        end
      end

    end
  end
end
