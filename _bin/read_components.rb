require 'rubygems'
require File.join File.dirname(__FILE__), '..', '_ext', 'tweakruby'
require 'yaml'
require_relative File.join '..', '_ext', 'repository'
require_relative File.join '..', '_ext', 'arquillian'

(components, modules_by_type) = YAML.load_file('../_tmp/datacache/components.yml')
prev_type = nil
modules_by_type.each do |type, modules|
  modules.each do |m|
    if not type.eql? prev_type
      puts m.component.type_name
      prev_type = type
    end
    puts '  ' + m.name
  end
  prev_type = type
end
