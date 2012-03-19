require 'digest/md5'

module Identities
  module Gravatar
    # It appears that all github users have a gravatar_id
    AVATAR_URL_TEMPLATE = 'http://gravatar.com/avatar/%s?s=%i'
    FALLBACK_AVATAR_URL_TEMPLATE = 'https://community.jboss.org/people/sbs-default-avatar/avatar/%i.png'
    module IdentityHelper
      def avatar_url(size = 48)
        if !self.gravatar_id.nil?
          AVATAR_URL_TEMPLATE % [self.gravatar_id, size]
        else
          FALLBACK_URL_TEMPLATE % size
        end
      end
    end

    class Crawler
      API_URL_TEMPLATE = 'http://en.gravatar.com/%s.json'
      LANYRD_PROFILE_URL_TEMPLATE = 'http://lanyrd.com/profile/%s'
      def enhance(identity)
        identity.extend(IdentityHelper)
      end

      def crawl(identity)
        hash = identity.gravatar_id
        if hash.nil?
          hash = Digest::MD5.new().update(identity.email.downcase).hexdigest 
        end
        url = API_URL_TEMPLATE % hash
        response = RestClient.get(url) do |rsp, req, res, &blk|
          if rsp.code.eql? 404
            rsp = RestClient::Response.create('{}', rsp.net_http_res, rsp.args)
            rsp.instance_variable_set(:@code, 200)
            rsp
          else
            rsp.return!(req, res, &blk)
          end
        end

        data = JSON.parse response

        if data.empty?
          return
        end

        entry = data['entry'].first

        keys_to_gravatar = {
          'id' => 'id',
          'hash' => 'hash',
          'profileUrl' => 'profile_url'
        }
        identity.gravatar = OpenStruct.new(entry.select {|k, v|
          !v.to_s.strip.empty? and keys_to_gravatar.has_key? k
        }.inject({}) {|h,(k,v)| h.store(keys_to_gravatar[k], v); h})

        keys_to_identity = {
          'preferredUsername' => 'preferred_username',
          'displayName' => 'name_cloak',
          'aboutMe' => 'bio',
          'currentLocation' => 'location'
        }
        identity.merge!(OpenStruct.new(entry.select {|k, v|
          !v.to_s.strip.empty? and keys_to_identity.has_key? k
        }.inject({}) {|h,(k,v)| h.store(keys_to_identity[k], v); h}), false)

        # TODO check if we need a merge here
        if entry.has_key? 'name' and !entry['name'].to_s.strip.empty?
          if identity.names.nil?
            identity.names = OpenStruct.new(entry['name'])
          end
          if identity.name.nil?
            identity.name = identity.names.formatted
          end
        end

        # ?? this only makes sense if we didn't get the hash from the e-mail
        if entry.has_key? 'email' and !entry['email'].to_s.strip.empty? and !identity.email.eql? entry['email']
          if identity.emails.nil?
            identity.emails = [identity.email, entry['email']]
          else
            identity.emails = identity.emails | [identity.email, entry['email']]
          end
        end

        (entry['accounts'] || []).each do |a|
          astruct = OpenStruct.new(a)
          if identity.send(a['shortname']).nil?
            identity.send(a['shortname'] + '=', astruct)
          else
            identity.send(a['shortname']).merge!(astruct)
          end
        end

        # QUESTION do we need the speaker flag check?
        if identity.speaker and !identity.twitter.nil? and identity.lanyrd.nil?
          identity.lanyrd = OpenStruct.new({
            :username => identity.twitter.username,
            :profile_url => LANYRD_PROFILE_URL_TEMPLATE % identity.twitter.username
          })
        end

        (entry['urls'] || []).each do |u|
          identity.urls = [] if identity.urls.nil?
          identity.urls << OpenStruct.new(u)
          if identity.blog.to_s.empty? and u['title'] =~ /blog/i
            identity.blog = u['value']
          end
          if identity.homepage.to_s.empty? and u['title'] =~ /personal/i
            identity.homepage = u['value']
          end
        end
      end
    end
  end
end
