# typed: strict
# frozen_string_literal: true

class CommentAction
  class ValidationResult
    sig { params(errors: T.nilable(T::Array[String])).void }
    def initialize(errors = nil)
      @errors = T.let(errors || [], T::Array[String])
    end

    sig { returns(T::Boolean) }
    def valid? = @errors.empty?

    sig { returns(String) }
    def error_message = @errors.join(", ")

    sig { params(error: String).void }
    def <<(error)
      @errors << error
    end

    sig { params(other: ValidationResult).returns(ValidationResult) }
    def +(other)
      ValidationResult.new(@errors + other.errors)
    end

    protected

    sig { returns(T::Array[String]) }
    attr_reader :errors
  end

  sig do
    params(
      repository: Repositories::IRepository,
      comment_type: String,
      comment_id: Integer,
    ).returns(T::Array[Record])
  end
  def self.for(repository:, comment_type:, comment_id:)
    Store.new(repository:, comment_type:, comment_id:).load
  end

  sig do
    params(
      repository: Repositories::IRepository,
      comment_type: String,
      comment_id: Integer,
      actions: T.nilable(T::Array[T::Hash[String, String]])
    ).void
  end
  def self.upsert!(repository:, comment_type:, comment_id:, actions:)
    return if actions.nil?

    GitHub.logger.info(
      "message": "Upserting comment actions",
      "gh.repo.id": repository.id,
      "gh.comment.id": comment_id,
      "gh.comment.type": comment_type,
      "code.function": "upsert!",
      "code.namespace": "CommentAction",
    )

    store = Store.new(repository:, comment_type:, comment_id:)

    if actions.any?
      store.persist(actions)
    else
      store.delete
    end
  end

  # Like `.upsert!`, but errors are logged instead of being raised.
  sig do
    params(
      repository: Repositories::IRepository,
      comment_type: String,
      comment_id: Integer,
      actions: T.nilable(T::Array[T::Hash[String, String]])
    ).returns(T::Boolean)
  end
  def self.safe_upsert(repository:, comment_type:, comment_id:, actions:)
    upsert!(repository:, comment_type:, comment_id:, actions:)
    true
  rescue => e # rubocop:disable Lint/RescueException
    GitHub.logger.error(
      "message": "Error writing comment actions",
      "exception": e,
      "gh.repo.id": repository.id,
      "gh.comment.id": comment_id,
      "gh.comment.type": comment_type,
      "code.function": "safe_upsert",
      "code.namespace": "CommentAction",
    )
    false
  end

  class Store
    include GitHub::Memoizer

    KV_KEY_PATTERN = "pull_requests/comment_actions/%{class}%{id}"

    sig do
      params(
        repository: Repositories::IRepository,
        comment_type: String,
        comment_id: Integer,
      ).void
    end
    def initialize(repository:, comment_type:, comment_id:)
      @repository = T.let(repository, Repositories::IRepository)
      @comment_type = T.let(comment_type, String)
      @comment_id = T.let(comment_id, Integer)
    end

    sig { params(actions: T::Array[T::Hash[String, String]]).void }
    def persist(actions)
      valid_records, validation_result = deserialize_and_validate(actions)

      if validation_result.valid?
        kv_store.set(kv_key, valid_records.map(&:serialize).to_json)
      else
        raise ArgumentError, "Invalid actions: #{validation_result.error_message}"
      end
    end

    sig { void }
    def delete
      kv_store.del(kv_key)
    end

    sig { returns(T::Array[CommentAction::Record]) }
    def load
      json = kv_store.get(kv_key).value { nil }
      return [] if json.blank?

      data = JSON.parse(json)
      valid_records, _ = deserialize_and_validate(data)

      valid_records
    rescue JSON::ParserError => e
      GitHub.logger.error(
        "message": "Error loading comment actions",
        "exception": e,
        "gh.repo.id": @repository.id,
        "gh.comment.id": @comment_id,
        "gh.comment.type": @comment_type,
        "code.function": "load",
        "code.namespace": "CommentAction::Store",
      )

      []
    end

    private

    sig { params(actions: T::Array[T::Hash[String, String]]).returns([T::Array[Record], ValidationResult]) }
    def deserialize_and_validate(actions)
      combined_validation_result = ValidationResult.new
      records = T.let([], T::Array[Record])

      actions.each do |action|
        if record_class = Record::CLASS_BY_TYPE_NAME[T.unsafe(action["type"])]
          record, validation_result = record_class.deserialize(action)
          combined_validation_result += validation_result
          records << record unless record.nil?
        else
          valid_types = Record::CLASS_BY_TYPE_NAME.keys
            .map { |name| "`#{name}`" }
            .to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
          combined_validation_result << "`type` must be one of #{valid_types}"
        end
      end

      [records, combined_validation_result]
    end

    sig { returns(String) }
    def kv_key = KV_KEY_PATTERN % { class: @comment_type, id: @comment_id }

    sig { returns(GitHub::KV) }
    memoize def kv_store
      PullRequests::KV.for_repository(@repository)
    end
  end

  module Record
    extend T::Helpers

    sealed!
    interface!

    requires_ancestor { Object }

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(T::Hash[String, String]) }
    def serialize; end

    class CopilotChatAction < T::Struct
      include Record

      TYPE_NAME = "copilot-chat"

      const :name, String
      const :prompt, String

      sig { params(hash: T::Hash[String, String]).returns([T.nilable(CopilotChatAction), ValidationResult]) }
      def self.deserialize(hash)
        name, prompt = hash.values_at("name", "prompt")

        validation_result = ValidationResult.new
        validation_result << "`name` is required" if name.blank?
        validation_result << "`prompt` is required for `copilot-chat` actions" if prompt.blank?

        if validation_result.valid?
          [new(name: T.must(name), prompt: T.must(prompt)), validation_result]
        else
          [nil, validation_result]
        end
      rescue => e # rubocop:disable Lint/RescueException
        GitHub.logger.error(
          "message": "Error deserializing a copilot-chat comment action",
          "exception": e,
          "gh.comment_action.hash": hash.to_json,
          "code.function": "deserialize",
          "code.namespace": "CommentAction::Record::CopilotChatAction",
        )
        [nil, ValidationResult.new(["unexpected error"])]
      end

      sig { override.returns(T::Hash[String, String]) }
      def serialize
        {
          type: TYPE_NAME,
          name:,
          prompt:,
        }
      end
    end

    class LinkAction < T::Struct
      include Record

      TYPE_NAME = "link"

      const :name, String
      const :url, String

      sig { params(hash: T::Hash[String, String]).returns([T.nilable(LinkAction), ValidationResult]) }
      def self.deserialize(hash)
        name, url = hash.values_at("name", "url")

        validation_result = ValidationResult.new
        validation_result << "`name` is required" if name.blank?

        if url.blank?
          validation_result << "`url` is required for `link` actions"
        else
          uri = URI.parse(url) rescue nil
          if !uri.is_a?(URI::HTTP)
            validation_result << "`url` must be a well-formed Web (HTTP) link"
          elsif GitHub.host_name != uri.host
            validation_result << "`url` must be a GitHub link (i.e. a link to #{GitHub.host_name})"
          end
        end

        if validation_result.valid?
          [new(name: T.must(name), url: T.must(url)), validation_result]
        else
          [nil, validation_result]
        end
      rescue => e # rubocop:disable Lint/RescueException
        GitHub.logger.error(
          "message": "Error deserializing a link comment action",
          "exception": e,
          "gh.comment_action.hash": hash.to_json,
          "code.function": "deserialize",
          "code.namespace": "CommentAction::Record::LinkAction",
        )
        [nil, ValidationResult.new(["unexpected error"])]
      end

      sig { override.returns(T::Hash[String, String]) }
      def serialize
        {
          type: TYPE_NAME,
          name:,
          url:,
        }
      end
    end

    CLASS_BY_TYPE_NAME = T.let(
      {
        CopilotChatAction::TYPE_NAME => CopilotChatAction,
        LinkAction::TYPE_NAME => LinkAction,
      },
      T::Hash[
        String,
        T.any(
          T.class_of(CopilotChatAction),
          T.class_of(LinkAction),
        )
      ]
    )
  end
end
