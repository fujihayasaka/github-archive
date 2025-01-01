# typed: true
# frozen_string_literal: true

module Storage
  class PolicyCreator
    def initialize(*models)
      @key_to_model = {}
      @policy_models = {}
      models.each { |m| add_model(m) }
    end

    def for(key)
      return nil if key.blank?
      @policy_models[key.to_sym]
    end

    def asset_uri(asset)
      [@key_to_model.invert[asset.class].to_s, asset.id].join("/")
    end

    def add_model(model)
      key = model.uploadable_policy_path
      @key_to_model[key] = model

      attribs = model.uploadable_policy_attributes.map { |a| a.to_s }
      @policy_models[key] = PolicyModel.new(model, attribs)
      self
    end

    class PolicyModel
      attr_accessor :model, :attributes

      class AccessControl < Platform::Authorization::Permission
        attr_reader :env

        def initialize(context)
          context[:origin] = Platform::ORIGIN_API
          @env = {}
          super
        end

        def graphql_request?
          false
        end
      end

      def initialize(model = nil, attributes = nil)
        @model = model
        @attributes = attributes
      end

      def access_allowed?(user, verb, options = nil)
        access_grant(user, verb, options).access_allowed?
      end

      def access_grant(user, verb, options = nil)
        options ||= {}
        options[:verb] = verb
        options[:user] = user
        Api::AccessControl.access_grant(options)
      end

      def create(user, params)
        attribs = filter_attributes(params)
        model.create_for_policy(user, attribs)
      end

      def filter_attributes(params)
        attributes.inject({}) { |a, k| a.update(k => params[k]) }
      end
    end
  end
end
