# typed: true
# frozen_string_literal: true

module Elastomer
  class Router

    module TemplateMethods
      def writable_templates(obj, cluster = nil)
        template_type = to_template_type(obj)
        templates = SearchIndexTemplateConfiguration.where(template_type: template_type, is_writable: true)

        if !cluster.nil?
          templates = templates.where(cluster: cluster)
        end

        templates
      end

      def primary_template(obj, cluster = nil)
        template_type = to_template_type(obj)
        templates = SearchIndexTemplateConfiguration.where(template_type: template_type, is_primary: true)

        if !cluster.nil?
          templates = templates.where(cluster: cluster)
        end
        templates.first
      end

      def next_available_template_name(obj)
        template_type = to_template_type(obj)

        model = SearchIndexTemplateConfiguration.
            select(:template_version).
            where(template_type: template_type).
            order("template_version DESC").first

        version = model && model.template_version || 0
        slicer = Elastomer.env.lookup_slicer(template_type)
        slicer.index_version = version + 1
        slicer.fullname
      end

      # Internal: Given either an Index class or a type String ("audit_log") or
      # template name ("audit_log-12"), return a Straing that is a valid
      # `template_type` for database lookups.
      #
      # obj - an Index class or an template type String
      #
      # Returns a `template_type` String
      def to_template_type(obj)
        return obj.logical_index_name if obj.respond_to?(:logical_index_name)

        slicer = ::Elastomer::Slicer.new(postfix: nil)
        obj = obj.to_s
        begin
          slicer.fullname = obj
        rescue ArgumentError
          slicer.index = obj
        end
        slicer.index
      end
    end
  end
end
