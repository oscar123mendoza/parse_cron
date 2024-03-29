# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "parse_cron/version"

Gem::Specification.new do |s|
  s.name        = "parse_cron"
  s.version     = Parse::Cron::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Oscar Mendoza"]
  s.email       = ["chi23bearts@gmail.com"]
  s.homepage    = "https://github.com/siebertm/parse_cron"
  s.summary     = %q{Parses cron expressions and calculates the next occurence}
  s.description = %q{Parses cron expressions and calculates the next occurence}

  s.rubyforge_project = "parse_cron"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency 'rspec', '~>2.6.0'
end
