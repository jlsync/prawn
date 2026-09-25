# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# Use the jlsync fork of pdf-core, which carries serialization performance
# fixes not yet in a pdf-core release.
gem 'pdf-core', github: 'jlsync/pdf-core'

# Evaluate Gemfile.local if it exists
if File.exist?("#{__FILE__}.local")
  instance_eval(File.read("#{__FILE__}.local"), "#{__FILE__}.local")
end
