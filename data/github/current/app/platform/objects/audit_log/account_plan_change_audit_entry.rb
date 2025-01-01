# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class AccountPlanChangeAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a account.plan_change event."

        visibility :under_development
        minimum_accepted_scopes ["read:user", "admin:org", "admin:enterprise"]


        # Determine whether the viewer can access this object via the API (called internally).
        # This is where Egress checks for OAuth scopes and GitHub Apps go.
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_api_can_access?(permission, audit_entry)
          permission.async_api_can_access_audit_entry?(audit_entry)
        end

        # Determine whether the viewer can see this object (called internally).
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_viewer_can_see?(permission, audit_entry)
          permission.async_viewer_can_see_audit_entry?(audit_entry)
        end

        implements_node_with_document_id(prefix: "APCAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :coupon, String, null: true, description: "The applied coupon."
        def coupon
          @object.get :coupon
        end

        field :data_pack_count, Integer, null: true, description: "The number of Git LFS Data packs applicable."
        def data_pack_count
          @object.get :asset_packs
        end

        field :data_pack_count_was, Integer, null: true, description: "The previous number of Git LFS Data packs."
        def data_pack_count_was
          @object.get :old_data_packs
        end

        field :plan_duration, Enums::AuditLog::AccountPlanChangeAuditEntryDuration, null: true, description: "The billing cycle duration."
        def plan_duration
          @object.get :plan_duration
        end

        field :plan_duration_was, Enums::AuditLog::AccountPlanChangeAuditEntryDuration, null: true, description: "The previous billing cycle duration."
        def plan_duration_was
          @object.get :old_plan_duration
        end

        field :plan_name, String, null: true, description: "The plan name."
        def plan_name
          @object.get :plan
        end

        field :plan_name_was, String, null: true, description: "The previous plan name."
        def plan_name_was
          @object.get :old_plan
        end

        field :seat_count, Integer, null: true, description: "The number of seats."
        def seat_count
          @object.get :seats
        end

        field :seat_count_was, Integer, null: true, description: "The previous number of seats."
        def seat_count_was
          @object.get :old_seats
        end

        # Internal Fields

        field :did_plan_change, Boolean, null: false, visibility: :internal, description: "Did the plan change."
        def did_plan_change
          plan_name_was != plan_name
        end

        field :did_plan_duration_change, Boolean, null: false, visibility: :internal, description: "Did the plan duration change."
        def did_plan_duration_change
          plan_duration_was != plan_duration
        end

        field :did_pricing_change_to_per_seat, Boolean, null: false, visibility: :internal, description: "Did the plan change adjust the pricing model to per seat."
        def did_pricing_change_to_per_seat
          plan_name_was != plan_name && per_seat_plan?(plan_name)
        end

        field :did_pricing_change_to_per_repo, Boolean, null: false, visibility: :internal, description: "Did the plan change adjust pricing model to per repo."
        def did_pricing_change_to_per_repo
          plan_name_was != plan_name && per_seat_plan?(plan_name_was)
        end

        field :did_seat_count_change, Boolean, null: false, visibility: :internal, description: "Did the plan change adjust the number of seats."
        def did_seat_count_change
          per_seat_plan?(plan_name) && seat_count_was != seat_count
        end

        field :filled_seat_count, Integer, null: true, visibility: :internal, description: "The number of filled seats."
        def filled_seat_count
          @object.get :filled_seats
        end

        field :private_repository_count, Integer, null: true, visibility: :internal, description: "The number of private repositories."
        def private_repository_count
          @object.get :private_repositories_count
        end

        field :public_repository_count, Integer, null: true, visibility: :internal, description: "The number of public repositories."
        def public_repository_count
          @object.get :public_repositories_count
        end

        field :note, String, null: true, visibility: :internal, description: "A note related to this plan change."
        def note
          @object.get :note
        end

        field :reason, String, null: true, visibility: :internal, description: "A human readable reason for this plan change."
        def reason
          @object.get :reason
        end

        field :team_count, Integer, null: true, visibility: :internal, description: "The number of teams."
        def team_count
          @object.get :teams_count
        end

        field :terms_of_service_sha, String, null: true, visibility: :internal, description: "The signature for the applicable Terms of Service for this account."
        def terms_of_service_sha
          @object.get :tos_sha
        end

        private

        def per_seat_plan?(name)
          GitHub::Plan.find(name)&.per_seat? || false
        end
      end
    end
  end
end
