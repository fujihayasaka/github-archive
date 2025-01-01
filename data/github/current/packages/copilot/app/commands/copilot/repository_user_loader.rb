# typed: strict
# frozen_string_literal: true

module Copilot
  class RepositoryUserLoader < Command

    UserInsert = T.type_alias { { user_id: Integer, role: String } }

    sig { returns(::Repository) }
    attr_reader :repository

    sig { returns(Copilot::EngagedOssRepository) }
    attr_reader :engaged_oss_repository

    sig { returns(Integer) }
    attr_reader :deleted_count

    sig { returns(T::Array[UserInsert]) }
    attr_reader :to_insert_users

    sig { params(repository: ::Repository).void }
    def initialize(repository)
      @repository             = repository
      @engaged_oss_repository = T.let(T.must(Copilot::EngagedOssRepository.find_by(repository_id: repository.id)), Copilot::EngagedOssRepository)
      @deleted_count          = T.let(0, Integer)
      @to_insert_users        = T.let(Array.new, T::Array[UserInsert])
    end

    # 1. Delete existing Copilot::EngagedOssUser for this repository
    # 2. Find all users who have contributed to this repository
    # 3. Create a Copilot::EngagedOssUser for each user
    sig { override.void }
    def perform
      delete_old_records
      load_new_records
      insert_new_records
    end

    sig { void }
    def delete_old_records
      GitHub.logger.with_named_tags("gh.repo.id" => repository.id, "gh.copilot.engaged_oss_repository.id" => engaged_oss_repository.id) do
        GitHub.logger.info("Deleting existing users for repository")
        @deleted_count = with_write do
          Copilot::EngagedOssUser.where(repository_id: engaged_oss_repository.id).delete_all
        end
        GitHub.logger.info("Deleted existing users for repository", "gh.copilot.count" => deleted_count)
      end
    end

    sig { void }
    def load_new_records
      GitHub.logger.with_named_tags("gh.repo.id" => repository.id, "gh.copilot.engaged_oss_repository.id" => engaged_oss_repository.id) do
        GitHub.logger.info("Loading new users for repository")
        admins      = load_admins
        GitHub.logger.info("Loaded admins for repository", "gh.copilot.count" => admins.size)
        writers     = load_writers
        GitHub.logger.info("Loaded writers for repository", "gh.copilot.count" => writers.size)
        maintainers = load_maintainers
        GitHub.logger.info("Loaded maintainers for repository", "gh.copilot.count" => maintainers.size)
        users = admins.merge(writers).merge(maintainers)

        # Deduplicate the set by user id
        @to_insert_users = users.group_by { |user| user[:user_id] }.map do |_, v|
          T.must(
            v.find { |x| x[:role] == "admin" } ||
            v.find { |x| x[:role] == "write" } ||
            v.find { |x| x[:role] == "maintain" }
          )
        end
        GitHub.logger.info("Loaded new users for repository", "gh.copilot.count" => to_insert_users.size)
      end
    end

    sig { void }
    def insert_new_records
      GitHub.logger.with_named_tags("gh.repo.id" => repository.id, "gh.copilot.engaged_oss_repository.id" => engaged_oss_repository.id) do
        GitHub.logger.info("Inserting new users for repository", "gh.copilot.count" => to_insert_users.size)
        user_inserts = to_insert_users.inject([]) do |inserts, user|
          inserts << {
            repository_id: engaged_oss_repository.id,
            user_id: user[:user_id],
            language: T.must(engaged_oss_repository.language_name).name,
            role: user[:role],
          }
          inserts
        end

        user_inserts.each_slice(1000).each_with_index do |chunk, index|
          chunk_size = chunk.size
          GitHub.logger.info("Inserting new users for repository", "gh.copilot.count" => chunk_size, "gh.copilot.index" => index)
          with_write do
            Copilot::EngagedOssUser.insert_all(chunk)
          end
          GitHub.logger.info("Inserted new users for repository", "gh.copilot.count" => chunk_size, "gh.copilot.index" => index)
        end
      end
    end

    sig { returns(T::Set[UserInsert]) }
    def load_admins
      admin_ids = repository.user_ids_with_privileged_access(min_action: :admin).uniq || []

      admin_ids = UserRole.where(target: repository).inject(admin_ids) do |ids, user_role|
        role = user_role.role
        next ids unless role.present?

        # we need to check if this is the preset admin role
        if role.preset?
          next ids unless role.admin? # skip if this isn't the preset admin role
        else
          # if this doesn't derive from the preset admin role, skip
          next ids unless role.base_role == Role.admin_role
        end

        ids << user_role.actor.id unless ids.include?(user_role.actor.id)
        ids
      end

      users = admin_ids.inject(Set.new) do |users, user_id|
        users << {
          user_id: user_id,
          role: "admin",
        }
        users
      end

      users
    end

    sig { returns(T::Set[UserInsert]) }
    def load_writers
      writer_ids = repository.user_ids_with_privileged_access(min_action: :write).uniq || []

      writer_ids = UserRole.where(target: repository).inject(writer_ids) do |ids, user_role|
        role = user_role.role
        next ids unless role.present?

        # we need to check if this is the preset write role
        if role.preset?
          next ids unless role.write? # skip if this isn't the preset write role
        else
          # if this doesn't derive from the preset write role, skip
          next ids unless role.base_role == Role.write_role
        end

        ids << user_role.actor.id unless ids.include?(user_role.actor.id)
        ids
      end

      users = writer_ids.inject(Set.new) do |users, user_id|
        users << {
          user_id: user_id,
          role: "write",
        }
        users
      end

      users
    end

    sig { returns(T::Set[UserInsert]) }
    def load_maintainers
      maintainer_ids = UserRole.where(target: repository).inject(Array.new) do |ids, user_role|
        role = user_role.role
        next ids unless role.present?

        # we need to check if this is the preset maintain role
        if role.preset?
          next ids unless role.maintain? # skip if this isn't the preset maintain role
        else
          # if this doesn't derive from the preset maintain role, skip
          next ids unless role.base_role == Role.maintain_role
        end

        ids << user_role.actor.id unless ids.include?(user_role.actor.id)
        ids
      end

      users = maintainer_ids.inject(Set.new) do |users, user_id|
        users << {
          user_id: user_id,
          role: "maintain",
        }
        users
      end

      users
    end
  end
end
