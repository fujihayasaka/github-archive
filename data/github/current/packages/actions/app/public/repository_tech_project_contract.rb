# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

class RepositoryTechProjectContract
  attr_accessor :path, :stacks, :size_of_project

  def initialize(path, stacks)
    @path = path
    @stacks = stacks
    @size_of_project = project_size
  end

  def get_stack_percentages
    return @stack_percentages if @stack_percentages
    @stack_percentages = Hash.new

    stacks.each do |stack|
      if stack.is_language?
        @stack_percentages[stack] = (stack.size.to_f / size_of_project)
      else
        @stack_percentages[stack] = 0
      end
    end

    @stack_percentages.sort_by { |_k, v| v }.reverse.to_h
  end

  def project_size
    project_size = 0
    return project_size if stacks.nil?

    stacks.each do |stack|
      if stack.is_language?
        project_size += stack.size
      end
    end

    project_size
  end
end
