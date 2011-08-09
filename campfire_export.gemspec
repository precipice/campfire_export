# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "campfire_export/version"

Gem::Specification.new do |s|
  s.name        = "campfire_export"
  s.version     = CampfireExport::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Marc Hedlund"]
  s.email       = ["marc@precipice.org"]
  s.license     = "Apache 2.0"
  s.homepage    = "https://github.com/precipice/campfire_export"
  s.summary     = %q{Export transcripts and uploaded files from your 37signals' Campfire account.}
  s.description = s.summary

  s.rubyforge_project = "campfire_export"
  s.required_ruby_version = '>= 1.8.7'
  
  s.add_development_dependency "bundler",  "~> 1.0.15"
  s.add_development_dependency "fuubar",   "~> 0.0.5"
  s.add_development_dependency "rspec",    "~> 2.6.0"
  s.add_dependency "tzinfo",   "~> 0.3.29"
  s.add_dependency "httparty", "~> 0.7.8"
  s.add_dependency "nokogiri", "~> 1.4.5"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
