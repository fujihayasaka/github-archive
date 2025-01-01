# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class Base < Platform::Objects::Base
        def self.load_from_global_id(document_id)
          Audit.load_from_global_id(document_id)
        end

        # Subclasses should call this to add new-format global ID definitions.
        #
        # Under the hood, this calls `implements_node` which configures and ID parser and adds the `id` field.
        #
        # @param [prefix] An all-caps prefix to use at the beginning of new-format Global IDs
        # @param [allow_longer_prefix] If `prefix` is longer than 6 letters, pass `true` here.
        #    (Maybe we could just do that automatically -- I didn't want to make it _too_ easy to make really big prefixes though.
        #    Feel free to change it if your experience proves otherwise. Maybe the whole limit should just be lifted...)
        # @return [void]
        def self.implements_node_with_document_id(prefix:)
          if /\A[A-Z]+\Z/ !~ prefix
            raise Platform::Errors::Internal, "`prefix:` must be /[A-Z]+/, not: #{prefix.inspect}"
          end
          template_prefix = prefix.downcase.to_sym
          implements_node(
              as: prefix,
              templates: [[template_prefix, :document_id]],
              allow_longer_prefix: true,
              uses_database_id: false,
              ready_date: Platform::Helpers::GlobalId::COHORT_1
            ) do |audit_log_entry|
            {
              prefix: template_prefix,
              document_id: audit_log_entry.id,
            }
          end
        end
      end
    end
  end
end
