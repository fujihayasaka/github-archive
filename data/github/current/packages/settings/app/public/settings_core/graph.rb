# typed: strict
# frozen_string_literal: true

module SettingsCore
  # A DAG representing a hierarchy of targetable resources for evaluating settings.
  # Each node in the graph corresponds to a targetable resource, and edges represent parent-child
  # relationships.
  class Graph
    extend T::Generic

    InternalValue = type_member

    sig { returns(String) }
    attr_reader :setting_name

    sig { returns(Targeting::Targetable) }
    attr_reader :node

    sig { returns(T::Array[Graph[InternalValue]]) }
    attr_reader :parents

    # Includes all settings stored at this node, including groups
    sig { returns(T::Array[ISetting]) }
    attr_reader :settings

    sig { returns(T::Array[Targeting::Targetable]) }
    attr_reader :all_resources

    # Value at this node from its parents before applying local settings
    # Includes results from parent rules
    sig { returns(T.nilable(InternalValue)) }
    attr_accessor :inherited_value

    # Final computed value at this node after applying local settings
    sig { returns(T.nilable(InternalValue)) }
    attr_accessor :final_value

    sig { params(setting_name: String, node: Targeting::Targetable, parents: T::Array[Graph[InternalValue]]).void }
    def initialize(setting_name, node, parents = [])
      @setting_name = setting_name
      @node = node
      @parents = parents
      @all_resources = T.let([node] + parents.flat_map(&:all_resources).uniq, T::Array[Targeting::Targetable])
      @settings = T.let([], T::Array[ISetting])
    end

    sig { returns(T::Array[T.untyped]) }
    def setting_values
      settings.select { |s| s.name == setting_name }.map(&:value)
    end

    sig { returns(T::Array[IRule]) }
    def rules
      settings.flat_map(&:rules)
    end

    sig { returns(T::Hash[Targeting::Targetable, InternalValue]) }
    def results_by_resource
      starting = if evaluated?
        { node => @final_value }
      else
        {}
      end
      parents.each_with_object(starting) do |child, acc|
        acc.merge!(child.results_by_resource)
      end
    end

    sig { returns(T::Boolean) }
    def evaluatable?
      parents.all?(&:evaluated?)
    end

    sig { returns(T::Boolean) }
    def evaluated?
      defined?(@computed_value) ? true : false
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def evaluation_payload
      {
        "targetable_id": node.internal_record.try(&:id),
        "targetable_type": node.internal_record.try(&:class)&.name,
        "applied_rules_count": rules.size,
        "applied_settings": settings.select { |s| s.name == setting_name }.map { |s| { "provider": s.provider_name, "value": s.value } },
        "inherited_value": inherited_value,
        "final_value": final_value,
        "parents": parents.map(&:evaluation_payload),
      }
    end

    sig { void }
    def log_evaluation
      GitHub.logger.info("Settings graph evaluation", {
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.setting.name": setting_name,
        "gh.setting.evaluation": evaluation_payload,
      })
    end
  end
end
