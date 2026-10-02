# frozen_string_literal: true

require 'matrix'

module Prawn
  # Stores the transformations that have been applied to the document.
  # @private
  module TransformationStack
    # rubocop: disable Metrics/ParameterLists, Naming/MethodParameterName

    # Add transformation to the stack.
    #
    # @param a [Number]
    # @param b [Number]
    # @param c [Number]
    # @param d [Number]
    # @param e [Number]
    # @param f [Number]
    # @return [void]
    def add_to_transformation_stack(a, b, c, d, e, f)
      @transformation_stack ||= [[]]
      @transformation_stack.last.push(
        [Float(a), Float(b), Float(c), Float(d), Float(e), Float(f)],
      )
    end

    # Save transformation stack.
    #
    # @return [void]
    def save_transformation_stack
      @transformation_stack ||= [[]]
      @transformation_stack.push(@transformation_stack.last.dup)
    end

    # Restore previous transformation.
    #
    # Effectively pops the last transformation off of the transformation stack.
    #
    # @return [void]
    def restore_transformation_stack
      @transformation_stack&.pop
    end

    # Get current transformation matrix. It's a result of multiplication of the
    # whole transformation stack with additional translation.
    #
    # @param x [Number]
    # @param y [Number]
    # @return [Array(Number, Number, Number, Number, Number, Number)]
    def current_transformation_matrix_with_translation(x = 0, y = 0)
      transformations = (@transformation_stack || [[]]).last
      return [1, 0, 0, 1, x, y] if transformations.nil? || transformations.empty?

      ma = 1
      mb = 0
      mc = 0
      md = 1
      me = 0
      mf = 0

      transformations.each do |a, b, c, d, e, f|
        new_ma = (ma * a) + (mc * b)
        new_mb = (mb * a) + (md * b)
        new_mc = (ma * c) + (mc * d)
        new_md = (mb * c) + (md * d)
        new_me = (ma * e) + (mc * f) + me
        new_mf = (mb * e) + (md * f) + mf
        ma = new_ma
        mb = new_mb
        mc = new_mc
        md = new_md
        me = new_me
        mf = new_mf
      end

      [ma, mb, mc, md, (ma * x) + (mc * y) + me, (mb * x) + (md * y) + mf]
    end
    # rubocop: enable Metrics/ParameterLists, Naming/MethodParameterName
  end
end
