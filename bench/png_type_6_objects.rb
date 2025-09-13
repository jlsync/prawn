# frozen_string_literal: true

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'prawn'

GC.disable

before = GC.stat

Prawn::Document.new do
  image("#{Prawn::DATADIR}/images/dice.png")
end.render

after = GC.stat

# Support Ruby 2.x (:total_allocated_object) and Ruby 3.x+ (:total_allocated_objects)
key = if after.key?(:total_allocated_objects)
        :total_allocated_objects
      else
        :total_allocated_object
      end

total = after[key] - before[key]

puts "allocated objects: #{total}"
