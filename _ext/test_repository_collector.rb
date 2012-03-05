require 'repository'
require 'arquillian'
require 'ostruct'
require 'yaml'

class OpenStruct
  def to_h()
    convert_to_hash(self)
  end

  private
  def convert_to_hash(ostruct)
    h = {}
    ostruct.marshal_dump().each {|k, v|
      if v.class == OpenStruct
        h[k] = convert_to_hash(v)
      elsif v.class == Array
        h[k] = []
        v.each {|i|
          if i.class == OpenStruct
            h[k] << convert_to_hash(i) 
          else
            h[k] << i
          end
        }
      else
        h[k] = v
      end
    }
    h
  end
end

s = OpenStruct.new
s.tmp_dir = '../_tmp'
s.modules = {}
r = Awestruct::Extensions::Repository::Collector.new(480465, 'sGiJRdK2Cq8Nz0TkTNAKyw')
r.execute(s)

if !s.modules.nil?
  File.open('modules.yml', 'w').write s.modules.map{|k, v|
    v.repository.delete_field('repo')
    {k => v.to_h}
  }.to_yaml
#  s.modules.each do |path, data|
#    puts path
#    data.releases.each do |r|
#      puts "- " + r.version
#    end
#  end
end
