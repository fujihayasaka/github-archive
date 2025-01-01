# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    class IssueFieldValue
      sig { params(permission: T.untyped, object: T.untyped).returns(::Promise[TrueClass]) }
      def self.async_api_can_access?(permission, object)
        object.async_issue.then do |issue|
          issue.async_repository.then do |repository|
            next false unless IssueFieldsFeature.enabled?(repository, actor: permission.viewer)

            permission.access_allowed?(
              :read_issue_field_values,
              resource: issue,
              issue_field_value: object,
              current_org: nil,
              current_repo: repository,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end
      end

      sig { params(permission: T.untyped, object: T.untyped).returns(::Promise[T::Boolean]) }
      def self.async_viewer_can_see?(permission, object)
        object.async_issue.then do |issue|
          issue.async_repository.then do |repository|
            next false unless IssueFieldsFeature.enabled?(repository, actor: permission.viewer)

            permission.access_allowed?(
              :read_issue_field_values,
              resource: issue,
              issue_field_value: object,
              current_org: nil,
              current_repo: repository,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end
      end

      sig { params(issue_field: T.untyped, issue: T.untyped, viewer: T.untyped, action: String).returns(T.untyped) }
      def self.create_or_update_field_value(issue_field:, issue:, viewer:, action:)
        field_id = Platform::Helpers::NodeIdentification.from_global_id(issue_field.field_id)[1].to_i

        if action == "create"
          existing_value = Issues.domain.issue_fields.get_issue_field_value(issue.repository_id, issue.id, field_id)
          if existing_value.present?
            raise Platform::Errors::Validation.new("A value for this field already exists on this issue.")
          end
        end

        field_value_attributes = if issue_field.respond_to?(:single_select_option_id) && issue_field.single_select_option_id.present?
          option_id = Platform::Helpers::NodeIdentification.from_global_id(issue_field.single_select_option_id)[1].to_i
          Issues::IssueFieldSingleSelectValueAttributes.new(
            field_id: field_id,
            option_id: option_id
          )
        elsif issue_field.respond_to?(:text_value) && issue_field.text_value.present?
          Issues::IssueFieldTextValueAttributes.new(
            field_id: field_id,
            text_value: issue_field.text_value
          )
        elsif issue_field.respond_to?(:number_value) && issue_field.number_value.present?
          Issues::IssueFieldNumberValueAttributes.new(
            field_id: field_id,
            number_value: issue_field.number_value
          )
        elsif issue_field.respond_to?(:date_value) && issue_field.date_value.present?
          Issues::IssueFieldDateValueAttributes.new(
            field_id: field_id,
            date_value: issue_field.date_value
          )
        else
          nil
        end

        if field_value_attributes.nil?
          raise Platform::Errors::Validation.new("You must provide a valid value to match the selected type.")
        end

        issue_attributes = Issues::UpdateIssueAttributes.new(issue_fields: [field_value_attributes])

        begin
          result = Issues.domain.update(issue, issue_attributes, viewer)
        rescue ActiveRecord::RecordInvalid => e
          raise Platform::Errors::Validation.new(e.message)
        end

        case result
        when GH::Result::Ok
          value = Issues.domain.issue_fields.get_issue_field_value(issue.repository_id, issue.id, field_value_attributes.field_id)
          { issue_field_value: value, issue: issue }
        when GH::Result::Error::Validation
          raise Platform::Errors::Validation.new(result.message)
        when GH::Result::Error
          raise Platform::Errors::Unprocessable.new(result.message)
        end
      end
    end
  end
end
