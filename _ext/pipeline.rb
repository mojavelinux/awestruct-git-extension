require File.join File.dirname(__FILE__), 'tweakruby'
require_relative 'restclient_extensions_enabler'
require_relative 'identities'
require_relative 'jira'
require_relative 'repository'
require_relative 'arquillian'
require_relative 'releases'
require_relative 'posts_helper'

Awestruct::Extensions::Pipeline.new {

  github_collector = Identities::GitHub::Collector.new(:auth_file => '.github-auth', :teams =>
    [
      {:id => 146647, :name => 'speaker'},
      {:id => 125938, :name => 'translator'},
      {:id => 146643, :name => 'core'}
    ]
  )

  extension Awestruct::Extensions::RestClientExtensions::EnableGetCache.new
  extension Awestruct::Extensions::RestClientExtensions::EnableJsonConverter.new
  extension Awestruct::Extensions::Identities::Storage.new
  Awestruct::Extensions::Jira::Project.new(self, 'ARQ:12310885')
  extension Awestruct::Extensions::Repository::Collector.new(480465, 'sGiJRdK2Cq8Nz0TkTNAKyw', :observers => [github_collector])
  extension Awestruct::Extensions::Identities::Collect.new(github_collector)
  extension Awestruct::Extensions::Identities::Crawl.new(
    Identities::GitHub::Crawler.new,
    Identities::Gravatar::Crawler.new,
    Identities::Confluence::Crawler.new('https://docs.jboss.org/author', :auth_file => '.jboss-auth',
        :identity_search_keys => ['name', 'username'], :assign_username_to => 'jboss_username'),
    Identities::JBossCommunity::Crawler.new
  )

  # Releases extension must be after jira and repository extensions and before posts extension 
  extension Awestruct::Extensions::Releases::Posts.new('/blog', :for_repo_owners => ['arquillian'], :since => '2011-01-01')

  extension Awestruct::Extensions::Posts.new('/blog')
  extension Awestruct::Extensions::Paginator.new(:posts, '/blog', :per_page => 5)
  extension Awestruct::Extensions::Tagger.new(:posts, '/blog', '/blog/tags', :per_page => 5)
  extension Awestruct::Extensions::TagCloud.new(:posts, '/blog/tags/index.html')
  helper Awestruct::Extensions::PostsHelper

  # ...

  extension Awestruct::Extensions::Identities::Cache.new
}
