# typed: true
# frozen_string_literal: true

class Actions::Graph
  attr_reader :name, :trigger, :workflow_job_runs

  def initialize(name:, trigger:, json:, workflow_job_runs:)
    @name = name
    @trigger = trigger
    @workflow_job_runs = workflow_job_runs
    @graph = {}
    @is_valid = false
    return if json.blank?
    @graph = GitHub::JSON.parse(json)
    if is_parsed_graph_valid?
      @graph.deep_symbolize_keys!
      @is_valid = true
    end
    rescue Yajl::ParseError
  end

  def is_valid?
    @is_valid
  end

  def stages
    @stages ||= (@graph[:stages] || []).map do |stage|
      Actions::Graph::Stage.new(stage: stage, workflow_job_runs: workflow_job_runs)
    end
  end

  def lines
    lines = []

    stages.each do |stage|
      stage.groups.each do |group|
        # Outgoing
        group.outputs.each do |out|
          lines << {
            from: group.dom_id,
            to: out
          }
        end
      end
    end

    lines
  end

  private

  def is_parsed_graph_valid?
    @graph.is_a?(Hash) && !@graph["stages"].nil?
  end
end
