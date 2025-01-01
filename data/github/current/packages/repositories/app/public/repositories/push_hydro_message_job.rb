# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Repositories
  class PushHydroMessageJob < RepositoryHydroMessageJob
    include GitHub::Memoizer

    class RepositoryNotFound < StandardError; end

    class DiscardJob < StandardError; end
    discard_on DiscardJob do |error|
      GitHub.logger.info(
        "Discarding push job. Reason: #{error.message}",
        "code.namespace": "PushHydroMessageJob",
        "code.function": "discard_on",
        "exception.type": error.class.name
      )
    end

    set_callback :perform, :around, :preload_repository
    set_callback :perform, :before, :skip_non_applicable_push
    set_callback :perform, :before, :set_push_context
    set_callback :perform, :before, :log_start
    set_callback :perform, :after,  :log_finish

    retry_on RepositoryNotFound, delay: :polynomially_longer, max_retries: 8

    class_attribute :applies_to_wikis, instance_writer: false
    def self.applies_to_wikis!
      self.applies_to_wikis = true
    end

    class_attribute :applies_to_empty_refs, instance_writer: false
    def self.applies_to_empty_refs!
      self.applies_to_empty_refs = true
    end

    attr_reader :request_context, :push_options, :oauth_access_id,
                :user_programmatic_access_id, :installation_id, :installation_type, :excluded_pull_ids,
                :merge_method, :merge_action, :request_id, :path, :total_ref_count, :ref_batch_number, :total_branch_count

    def initialize(protobuf:, headers:, schema:, timestamp:, timestamp_nano:, message:, queue:)
      super

      @request_context,
      @ref_updates,
      @pushed_at,
      @push_options,
      @oauth_access_id,
      @user_programmatic_access_id,
      @installation_id,
      @installation_type,
      @excluded_pull_ids,
      @merge_method,
      @merge_action,
      @pusher_login,
      @enabled_flags,
      @path,
      @total_ref_count,
      @ref_batch_number,
      @total_branch_count,
      @pusher_id = message.values_at(
        :request_context,
        :ref_updates,
        :pushed_at,
        :push_options,
        :oauth_access_id,
        :user_programmatic_access_id,
        :installation_id,
        :installation_type,
        :excluded_pull_ids,
        :merge_method,
        :merge_action,
        :pusher,
        :enabled_flags,
        :path,
        :total_ref_count,
        :ref_batch_number,
        :total_branch_count,
        :pusher_id
      )
      @request_id = @request_context&.dig(:request_id)
    end

    protected

    sig { returns(T::Array[T::Array[String]]) }
    memoize def filtered_refs
      @ref_updates.map { |ref_update| [ref_update[:ref], ref_update[:before], ref_update[:after]] }
                  .select { |_, before, after| before != after }
    end

    sig { returns(T::Array[Repositories::RefUpdate]) }
    memoize def ref_updates
      RepositoryPushRefSorter.new(filtered_refs).processed_refs.map do |(ref, before, after)|
        Repositories::RefUpdate.new(
          before: before,
          after: after,
          ref: ref,
          pusher: pusher,
          repository:,
        )
      end.select { |ref_update| ref_update.branch_or_tag? }
    end

    # Returns the ref update in `refs` that was made to the default branch, or `nil` if none exists.
    sig { returns(T.nilable(Repositories::RefUpdate)) }
    def push_includes_default_branch?
      qualified_default_branch_name = "refs/heads/#{repository.default_branch}"
      ref_updates.detect { |ref_update| ref_update.ref == qualified_default_branch_name }
    end

    sig { returns(Time) }
    def pushed_at
      Google::Protobuf::Timestamp.new(@pushed_at).to_time
    end

    sig { returns(User) }
    def pusher
      return @pusher if defined?(@pusher)
      @pusher = (@pusher_id && @pusher_id > 0 && User.find(@pusher_id)) || User.find_by_login(@pusher_login) || User.ghost
      hydrate_pusher_with_api_context if @pusher && !@pusher.ghost?
      @pusher
    end

    sig { returns(T::Boolean) }
    def wiki?
      path&.end_with?(".wiki.git")
    end

    sig { returns(T::Boolean) }
    def large_push?
      total_ref_count > Pushes::CommitsHelper::LARGE_REF_COUNT_THRESHOLD
    end

    sig { returns(T::Boolean) }
    def recordable_push?
      !(wiki?)
    end

    def preload_repository
      # Preload these associations so we do it within the context of the with_read/with_write block from the base job
      repository.network
      repository.owner&.business

      yield # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
    end

    def logging_context
      super.merge({
        "gh.repo.pushed_at": pushed_at,
        "gh.actor.name": @pusher_login,
        "gh.request_id": request_id
      })
    end

    sig { returns(HydroPushJobFlags) }
    def hydro_push_job_flags
      HydroPushJobFlags.new(@enabled_flags)
    end

    private

    def skip_non_applicable_push
      raise DiscardJob, "wiki (repo ID: #{repository.id})" if wiki? && !applies_to_wikis?
      raise DiscardJob, "non-existent repo (repo ID: #{repository.id})" if (repository.deleted? && !repository.soft_creating?) || !repository.exists_on_disk?
      raise DiscardJob, "no ref updates" if filtered_refs.empty? && !applies_to_empty_refs?
    end

    def set_push_context
      message_context = {
          actor: @pusher_login,
          actor_id: pusher.id,
          actor_ip: @request_context&.dig(:ip_address),
          request_id: @request_id
        }.merge(GitHub.context&.to_hash)

      GitHub.context.push(message_context)
      Failbot.push({
        "gh.repo.id": @repository_id,
        "gh.request_id": @request_id,
        "gh.job.name": self.class.name,
        "git.ref_updates": @ref_updates&.inspect,
        "gh.actor.name": @pusher_login,
      })
    end

    def ref_update_context
      ref_update = @ref_updates.first
      {
        "git.ref_updates.first.ref": ref_update&.dig(:ref),
        "git.ref_updates.first.before": ref_update&.dig(:before),
        "git.ref_updates.first.after": ref_update&.dig(:after),
        "git.ref_updates.count": @ref_updates.count
      }
    end

    def log_start
      GitHub.logger.info(
        "Performing #{self.class.name}",
        logging_context.merge(ref_update_context)
      )
    end

    def log_finish
      GitHub.logger.info(
        "Performed #{self.class.name}",
        logging_context.merge(ref_update_context)
      )
    end

    def pusher_lacks_api_context
      return @pusher_lacks_api_context if defined?(@pusher_lacks_api_context)
      pusher # make sure we've hydrated
      @pusher_lacks_api_context
    end

    def hydrate_pusher_with_api_context
      # Naively assume we will correctly hydrate, with a fallback to false.
      @pusher_lacks_api_context = false

      if @pusher.bot? && @installation_id&.nonzero? && @installation_type.present?
        @pusher.installation = case @installation_type
        when "IntegrationInstallation"
          IntegrationInstallation.find_by(id: @installation_id, integration: @pusher.integration)
        when "ScopedIntegrationInstallation"
          scoped_installation = ScopedIntegrationInstallation.find_by(id: @installation_id)
          scoped_installation&.integration == @pusher.integration ? scoped_installation : nil
        when "SiteScopedIntegrationInstallation"
          SiteScopedIntegrationInstallation.find_by(id: @installation_id, integration: @pusher.integration)
        end
      elsif @oauth_access_id&.nonzero?
        @pusher.oauth_access = OauthAccessTokens.domain.by_id(@oauth_access_id)
      elsif @user_programmatic_access_id&.nonzero?
        @pusher.programmatic_access = ProgrammaticAccess.find_or_nil(@user_programmatic_access_id)
      else
        @pusher_lacks_api_context = true
      end
      @pusher
    end
  end
end
