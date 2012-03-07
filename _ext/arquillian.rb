require 'rubygems'
require 'ostruct'
require 'git'
require 'fileutils'
require 'rexml/document'

module Awestruct::Extensions::Repository::Visitors
  module Clone
    include Base

    def visit(repository, site)
      repos_dir = File.join(site.tmp_dir, 'repos')
      FileUtils.mkdir_p(repos_dir)      
      clone_dir = File.join(repos_dir, repository.path)
      repo = nil
      if !File.directory?clone_dir
        puts "Cloning repository #{repository.clone_url} -> #{clone_dir}"
        repo = Git.clone(repository.clone_url, clone_dir)
      else
        puts "Using cloned repository #{clone_dir}"
        repo = Git.open(clone_dir)
        repo.pull('origin', 'origin/master')
      end
      repository.clone_dir = clone_dir
      repository.repo = repo
    end
  end

  module GenericModule
    include Base

    def handles(repository)
      repository.path != 'arquillian-showcase' and
          File.exist? File.join(repository.clone_dir, 'pom.xml')
      #repository.path =~ /^arquillian-(core$|(testrunner|container|extension)-.+$)/ and
      #    repository.path != 'arquillian-testrunner-jbehave'
    end

    # QUESTION: cache the root pom.xml? which rev?
    def visit(repository, site)
      repo = repository.repo
      m = OpenStruct.new
      m.repository = repository
      m.name = resolve_name(repository)
      m.desc = repository.desc
      m.groupId = resolve_group_id(repository)
      m.parent = true
      m.lead = resolve_lead(repository)
      m.license = 'Apache License 2.0'
      m.releases = []
      last_real_sha = nil
      repo.tags.select {|t| t.name =~ /^[1-9]\d*\.\d+\.\d+\.((Alpha|Beta|CR)[1-9]\d*|Final)$/ }.each do |t|
        release = OpenStruct.new
        release.version = t.name
        real_sha = repo.revparse(t.name + '^0')
        release.sha = real_sha
        release.http_url = repository.http_url + '/commit/' + real_sha
        commit = repo.gcommit(real_sha)
        committer = commit.committer
        release.date = committer.date
        release.released_by = OpenStruct.new
        release.released_by.name = committer.name
        release.released_by.email = committer.email
        #release.license = 'Apache License 2.0'
        # a follow-up extension will fill in the issues
        #release.issues = []
        release.committers = resolve_committers_between(repository, last_real_sha, real_sha)
        # not assigning to release since it can be very space intensive
        depversions = resolve_dep_versions(repository, release.version)
        release.compiledeps = []
        {
          'arquillian_core' => 'Arquillian Core',
          'org_jboss_arquillian_core' => 'Arquillian Core',
          'shrinkwrap_shrinkwrap' => 'ShrinkWrap Core',
          'shrinkwrap_descriptors' => 'ShrinkWrap Descriptors',
          'shrinkwrap_resolver' => 'ShrinkWrap Resolvers',
          'junit_junit' => 'JUnit',
          'testng_testng' => 'TestNG'
        }.each do |key, name|
          if depversions.has_key? key
            release.compiledeps << OpenStruct.new({:name => name, :key => key, :version => depversions[key]})
          end
        end
         m.releases << release
         last_real_sha = real_sha
      end
      # QUESTION put modules on repository? (can be more than one)
      site.modules[repository.path] = m
    end

    def resolve_name(repository)
      repo = repository.repo
      pom = REXML::Document.new(repo.cat_file(repo.revparse("HEAD:#{repository.relative_path}pom.xml")))
      pom.root.elements['name'].text.sub(/ (Aggregator|Parent)/, '')
    end

    def resolve_group_id(repository)
      repo = repository.repo
      pom = REXML::Document.new(repo.cat_file(repo.revparse("HEAD:#{repository.relative_path}pom.xml")))
      if !pom.root.elements['groupId'].nil?
        pom.root.elements['groupId'].text
      else
        pom.root.elements['parent'].elements['groupId'].text
      end
    end

    # TODO should track lead by release version (for historical reasons)
    def resolve_lead(repository)
      repo = repository.repo
      lead = OpenStruct.new
      pom = REXML::Document.new(repo.cat_file(repo.revparse("HEAD:#{repository.relative_path}pom.xml")))
      pom.each_element('/project/developers/developer') do |dev|
        # capture first developer as fallback lead
        if lead.nil?
          lead.name = dev.elements['name'].text
          lead.email = dev.elements['email'].text
        end

        if !dev.elements['roles'].nil?
          if !dev.elements['roles'].elements.find { |role| role.name.eql? 'role' and role.text =~ / Lead/ }.nil?
            lead.name = dev.elements['name'].text
            lead.email = dev.elements['email'].text
            break
          end
        end
      end
      if lead.name?.nil?
        # FIXME parameterize
        if repository.path == 'jboss-as'
          lead.name = 'Jason T. Greene'
          lead.email = 'jason.greene@redhat.com'
        else
          lead.name = 'Aslak Knutsen'
          lead.email = 'aslak@redhat.com'
        end
      end
      lead
    end

    def resolve_dep_versions(repository, rev)
      repo = repository.repo
      versions = {}
      ['pom.xml', 'build/pom.xml'].each do |path|
        begin
          sha = repo.revparse("#{rev}:#{path}")
        rescue
          # path is not present in revision
          next
        end
        pom = REXML::Document.new(repo.cat_file(repo.revparse("#{rev}:#{path}")))
        pom.each_element('/project/properties/*') do |prop|
          if prop.name.start_with? 'version.' and
              not prop.name =~ /[\._]plugin$/ and
              not prop.name =~ /\.maven[\._]/
            versions[prop.name.sub('version.', '').gsub('.', '_')] = prop.text
          end
        end
      end
      versions
    end

    def resolve_committers_between(repository, sha1, sha2)
      repo = repository.repo
      seen = {}
      log = repo.log(nil).path(repository.relative_path)
      if sha1.nil?
        log = log.object(sha2)
      else
        log = log.between(sha1, sha2)
      end
      log.map {|c|
        # grabbing e-mail so we can lookup their identity later
        OpenStruct.new({:name => c.author.name, :email => c.author.email, :commits => 0})
      }.select {|e|
        # This loop grabs unique authors by email and counts commits
        exists = seen.has_key? e.email
        seen[e.email] = e if !exists
        seen[e.email].commits += 1
        !exists
      }.sort {|a, b| a.name <=> b.name}
    end
  end

  module BomModule
    include Base

    def handles(repository)
      (File.exist? File.join(repository.clone_dir, 'bom', 'pom.xml') or
        Dir.glob(File.join(repository.clone_dir, '*-bom', 'pom.xml')).size > 0)
    end

    def visit(repository, site)
      m = site.modules[repository.path]
      if m.releases.size > 0
        m.bom = OpenStruct.new
        m.bom.groupId = m.groupId
        m.bom.artifactId = resolve_bom_artifact_id(repository, m.releases.last.version)
        m.bom.version = m.releases.last.version
        # TODO could include what the bom includes (perhaps expandable div w/ bom contents?)
      end
    end

    def resolve_bom_artifact_id(repository, tag)
      repo = repository.repo
      clone_dir = repository.clone_dir
      if repository.relative_path != ''
        clone_dir = File.join(clone_dir, repository.relative_path)
      end
      bom_dirname = 'bom'
      if !File.exist? File.join(clone_dir, 'bom', 'pom.xml')
        bom_dirname = File.basename(File.dirname(Dir.glob(File.join(clone_dir, '*-bom', 'pom.xml')).first))
      end
      pom = REXML::Document.new(repo.cat_file(repo.revparse("#{tag}:#{bom_dirname}/pom.xml")))
      pom.root.elements['artifactId'].text
    end
  end

  module PlatformModule
    include Base

    def handles(repository)
      repository.path == 'arquillian-core'
    end

    def visit(repository, site)
      m = site.modules[repository.path]
      m.type = 'platform'
      m.artifacts = [
        OpenStruct.new({:variant => 'JUnit', :coordinates =>
            OpenStruct.new({:groupId => 'org.jboss.arquillian.junit', :artifactId => 'arquillian-junit-container'})}),
        OpenStruct.new({:variant => 'TestNG', :coordinates =>
            OpenStruct.new({:groupId => 'org.jboss.arquillian.testng', :artifactId => 'arquillian-testng-container'})})
      ]
    end

  end

  module TestRunnerModule
    include Base

    def handles(repository)
      repository.path =~ /^arquillian\-testrunner\-.+/ and
          File.exist? File.join(repository.clone_dir, 'pom.xml')
      #repository.path =~ /^arquillian\-testrunner\-.+/ and
      #    repository.path != 'arquillian-testrunner-jbehave'
    end

    def visit(repository, site)
      m = site.modules[repository.path]
      m.type = 'testrunner'
    end
  end

  module ContainerModule
    include Base

    def handles(repository)
      repository.path =~ /^arquillian\-container\-.+/ or
          repository.path == 'jboss-as'
    end

    def visit(repository, site)
      m = site.modules[repository.path]
      m.type = 'container'
      m.containers = resolve_container_adapters(repository)
      m.containers.each do |container|
        populate_container_info(repository, container)
        container.groupId = m.groupId
      end
    end

    def resolve_container_adapters(repository)
      repo = repository.repo
      adapters = []
      pom = REXML::Document.new(repo.cat_file(repo.revparse("HEAD:#{repository.relative_path}pom.xml")))
      pom.each_element('/project/modules/module') do |mod|
        if mod.text =~ /([^-]+)-(remote|managed|embedded)(-(.+))?$/
          adapters << OpenStruct.new({:path => mod.text, :prefix => $1, :management => $2, :version => $4})
        end
      end
      adapters
    end

    def populate_container_info(repository, container)
      repo = repository.repo
      container.enrichers = []
      pom = REXML::Document.new(repo.cat_file(repo.revparse("HEAD:#{repository.relative_path}#{container.path}/pom.xml")))
      container.name = pom.root.elements['name'].text
      container.artifactId = pom.root.elements['artifactId'].text
      # FIXME also need to check common submodule
      pom.each_element('/project/dependencies/dependency') do |dep|
        if dep.elements['groupId'].text.eql? 'org.jboss.arquillian.testenricher'
          container.enrichers << dep.elements['artifactId'].text.sub(/^arquillian-testenricher-/, '')
        elsif dep.elements['groupId'].text.eql? 'org.jboss.arquillian.protocol'
          container.protocol = dep.elements['artifactId'].text.sub(/^arquillian-protocol-/, '')
        end
      end
    end
  end

  module ExtensionModule
    include Base

    def handles(repository)
      repository.path =~ /^arquillian\-extension\-.+/ 
    end

    def visit(repository, site)
      m = site.modules[repository.path]
      m.type = 'extension'
    end
  end
end
