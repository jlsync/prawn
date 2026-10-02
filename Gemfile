# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# Shared dev toolchain, consumed from the fork until it is released.
gem 'prawn-dev', '~> 0.7.0', git: 'https://github.com/jlsync/prawn-dev.git', branch: 'main'

# Use the jlsync forks of pdf-core and ttfunk, which carry performance fixes
# not yet in a release.
gem 'pdf-core', github: 'jlsync/pdf-core'
gem 'ttfunk', github: 'jlsync/ttfunk'

# prawn-manual_builder uses URI::RFC2396_PARSER, which uri gained in 0.13.1;
# Ruby 3.3.0 ships uri 0.13.0.
gem 'uri', '>= 0.13.1'

# Evaluate Gemfile.local if it exists
if File.exist?("#{__FILE__}.local")
  instance_eval(File.read("#{__FILE__}.local"), "#{__FILE__}.local")
end
