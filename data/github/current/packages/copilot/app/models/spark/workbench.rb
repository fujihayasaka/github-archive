# typed: strict
# frozen_string_literal: true

module Spark
  class Workbench < ApplicationRecord::Copilot
    include ::Repositories::BelongsToRepository

    self.table_name = "spark_workbenches"

    belongs_to :user, optional: false
    belongs_to :runtime_app, class_name: "Spark::RuntimeApp", optional: true
    belongs_to_repository_via_domain optional: true

    validates :uuid, presence: true, uniqueness: true
    validates :name, length: { maximum: 255 }
    has_many :iterations, class_name: "Spark::WorkbenchIteration", foreign_key: :spark_workbench_id, dependent: :destroy, inverse_of: :workbench
    has_many :favorites, class_name: "Spark::FavoriteWorkbench", foreign_key: :spark_workbench_id, dependent: :destroy, inverse_of: :workbench

    after_commit :delete_runtime_app, on: :destroy

    UUID_REGEXP = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    scope :for_uuid_strings, -> (workbench_ids) do
      binary_uuids = workbench_ids.map { |uuid| binary_uuid(uuid) }
      where(uuid: binary_uuids)
    end

    sig { params(user_id: Integer, workbench_id: String).returns(T.nilable(Spark::Workbench)) }
    def self.for_uuid_string(user_id, workbench_id)
      find_by(uuid: binary_uuid(workbench_id), user_id: user_id)
    end

    sig { params(user_id: Integer, workbench_id_or_friendly_name: String).returns(T.nilable(Spark::Workbench)) }
    def self.by_friendly_name_or_uuid(user_id, workbench_id_or_friendly_name)
      if workbench_id_or_friendly_name !~ UUID_REGEXP
        Spark::Workbench.joins(:runtime_app).find_by(user_id: user_id, runtime_app: { friendly_name: workbench_id_or_friendly_name })
      else
        Spark::Workbench.for_uuid_string(user_id, workbench_id_or_friendly_name)
      end
    end

    sig { void }
    def mark_initialized!
      update!(initialized: true)
    end

    sig { returns(String) }
    def uuid_string
      uuid.unpack1("H*").scan(/(.{8})(.{4})(.{4})(.{4})(.{12})/).first.join("-")
    end

    sig { params(value: String).void }
    def uuid_string=(value)
      self.uuid = self.class.binary_uuid(value)
    end

    sig { params(id: Integer).returns(T.nilable(Spark::Workbench)) }
    def self.for_cloud_environment_id(id)
      find_by(cloud_environment_id: id)
    end

    sig { params(formatted_uuid_string: String).returns(String) }
    def self.binary_uuid(formatted_uuid_string)
      sanitized_uuid_string = formatted_uuid_string.delete("-")
      [sanitized_uuid_string].pack("H*")
    end

    sig { returns(User) }
    def billable_owner
      # TODO: This needs to be determined based on their copilot plan.
      user
    end

    sig { void }
    def hide
      # In the future, "hiding" a Spark will flag it such that it is only visible to the owner and
      # staff, and it is hidden from the public.
      #
      # For now, our only option is to destroy the record so that nobody can see it.
      destroy
    end

    sig { void }
    def delete_runtime_app
      unless user.nil? || runtime_app.nil?
        SparkRuntimeApp.delete_runtime_app(user, T.must(runtime_app).permanent_name)
      end
    end

    # Override the auto-generated user method to have a non-nilable return type
    # since we have optional: false and validate presence
    sig { returns(User) }
    def user
      T.must(super)
    end
  end
end
