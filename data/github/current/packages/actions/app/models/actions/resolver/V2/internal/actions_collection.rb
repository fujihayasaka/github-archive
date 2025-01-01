# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/DoNotAllowNameWithOwner
# rubocop:disable GitHub/DoNotAllowLogin
# Disabled cops because `nwo` refers to the `nwo` attribute of the request we receive from launch.

# Holds all actions we want to resolve.
# Facilitates the routing of actions to different resolution flows.
# Initial classification is performed based on wheter an action ref is a semver or not.
# Further classification can be performed using the different methods provided by this class.
#
# Note that internal types can be used in client code
class Actions::Resolver::V2::Internal::ActionsCollection

  # A plain action providing the minimal API contract of providing a `nwo` and `ref`.
  # This can be served via a repository git ref.
  class Action < T::Struct

    prop :requested_nwo, String
    prop :processed_nwo, T.nilable(String)
    prop :ref, String

    def resolved_nwo
      processed_nwo || requested_nwo
    end

    def eql?(other)
      hash == other.hash
    end

    def ==(other)
      eql?(other)
    end

    def hash
      [requested_nwo, processed_nwo, ref].hash
    end
  end

  # A semver action containing the normalised semver.
  # This can't be served but first needs to be classified.
  class UnclassifiedSemverAction < T::Struct

    prop :requested_nwo, String
    prop :processed_nwo, T.nilable(String)
    prop :ref, String
    prop :normalised_semver, String

    def resolved_nwo
      processed_nwo || requested_nwo
    end

    def eql?(other)
      hash == other.hash
    end

    def ==(other)
      eql?(other)
    end

    def hash
      [requested_nwo, processed_nwo, ref, normalised_semver].hash
    end
  end

  # An action that was decided to be unresolvable during classification.
  # Examples are:
  # - A semver action that RMS wasn't able to resolve and was not allowed to fallback to a repository ref.
  # - An undecided or repository action that tried to resolve a deprecated action.
  #
  # Note that this class isn't used for actions that fail to resolve after classification happened.
  class UnservableAction < T::Struct

    prop :requested_nwo, String
    prop :processed_nwo, T.nilable(String)
    prop :ref, String
    prop :error, Symbol

    # normalised_semver is populated for semver actions only
    prop :normalised_semver, T.nilable(String)

    def resolved_nwo
      processed_nwo || requested_nwo
    end

    def eql?(other)
      hash == other.hash
    end

    def ==(other)
      eql?(other)
    end

    def hash
      [requested_nwo, processed_nwo, ref, normalised_semver, error].hash
    end
  end

  # A package action containing the normalised semver and the full semver.
  # Also contains additional metadata we got from RMS to be later included in the response for launch.
  class PackageAction < T::Struct

    prop :requested_nwo, String
    prop :processed_nwo, T.nilable(String)
    prop :ref, String
    prop :normalised_semver, String
    prop :full_semver, String
    prop :package_id, Integer
    prop :package_visibility, Symbol

    def resolved_nwo
      processed_nwo || requested_nwo
    end

    def eql?(other)
      hash == other.hash
    end

    def ==(other)
      eql?(other)
    end

    def hash
      [requested_nwo, processed_nwo, ref, normalised_semver, full_semver, package_id, package_visibility].hash
    end
  end

  sig { params(actions: T::Array[Actions::Resolver::V2::Internal::ActionsCollection::Action]).void }
  def initialize(actions)
    @semver_parser = Actions::Resolver::V2::Internal::SemverParser.new
    @unclassified_semver_actions, @repository_actions = extract_semver_actions(actions)

    @package_actions = []
    @unservable_actions = []
  end

  # Returns a copy of the unclassified semver actions.
  # This is important as we often iterate over this and then modify this collection by calling one of:
  # -`serve_semver_from_repository_ref!`
  # - `serve_semver_from_package_version!`
  # - `impossible_to_serve!`
  sig { returns(T::Array[UnclassifiedSemverAction]) }
  def unclassified_semver_actions
    @unclassified_semver_actions.clone
  end

  # Returns a copy of the package actions.
  sig { returns(T::Array[PackageAction]) }
  def package_actions
    @package_actions.clone
  end

  # Returns a copy of the repository actions.
  # This is important as we often iterate over this and then modify this collection by calling one of:
  # - `impossible_to_serve!`
  sig { returns(T::Array[Action]) }
  def repository_actions
    @repository_actions.clone
  end

  # Returns a copy of the unservable actions.
  sig { returns(T::Array[UnservableAction]) }
  def unservable_actions
    @unservable_actions.clone
  end

  # Marks a semver action as being served from the repository.
  sig { params(nwo: String, ref: String).void }
  def serve_semver_from_repository_ref!(nwo:, ref:)
    action = pop_unclassified(nwo: nwo, ref: ref)
    raise ArgumentError, "No undecided semver action found for #{nwo}@#{ref}" unless action

    # Drops the normalised semver, as we want to serve the original ref from the repository.
    repository_action = Action.new(
      requested_nwo: action.requested_nwo,
      processed_nwo: action.processed_nwo,
      ref: action.ref)

    @repository_actions << repository_action
  end

  # Marks a semver action as being served from packages.
  sig { params(nwo: String, ref: String, full_semver: String, package_id: Integer, package_visibility: Symbol).void }
  def serve_semver_from_package_version!(nwo:, ref:, full_semver:, package_id:, package_visibility:)
    action = pop_unclassified(nwo: nwo, ref: ref)
    raise ArgumentError, "No undecided semver action found for #{nwo}@#{ref}" unless action

    package_action = PackageAction.new(
      requested_nwo: action.requested_nwo,
      processed_nwo: action.processed_nwo,
      ref: action.ref,
      normalised_semver: action.normalised_semver,
      full_semver: full_semver,
      package_id: package_id,
      package_visibility: package_visibility)

    @package_actions << package_action
  end

  sig { params(nwo: String, ref: String, error: Symbol).void }
  def impossible_to_serve!(nwo:, ref:, error:)
    action = pop_unclassified(nwo: nwo, ref: ref) || pop_repository(nwo: nwo, ref: ref)
    raise ArgumentError, "No undecided semver or repository action found for #{nwo}@#{ref}" unless action

    unservable_action = case action
    when Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction
      UnservableAction.new(
        requested_nwo: action.requested_nwo,
        processed_nwo: action.processed_nwo,
        ref: action.ref,
        error: error,
        normalised_semver: action.normalised_semver)
    when Actions::Resolver::V2::Internal::ActionsCollection::Action
      UnservableAction.new(
        requested_nwo: action.requested_nwo,
        processed_nwo: action.processed_nwo,
        ref: action.ref,
        error: error)
    else
      T.absurd(action)
    end

    @unservable_actions << unservable_action
  end

  private

  sig { params(nwo: String, ref: String).returns(T.nilable(Actions::Resolver::V2::Internal::ActionsCollection::UnclassifiedSemverAction)) }
  def pop_unclassified(nwo:, ref:)
    @unclassified_semver_actions.each_with_index do |action, i|
      next unless action.requested_nwo == nwo

      if action.ref == ref
        @unclassified_semver_actions.delete_at(i)
        return action
      end
    end

    nil
  end

  sig { params(nwo: String, ref: String).returns(T.nilable(Actions::Resolver::V2::Internal::ActionsCollection::Action)) }
  def pop_repository(nwo:, ref:)
    @repository_actions.each_with_index do |action, i|
      next unless action.requested_nwo == nwo

      if action.ref == ref
        @repository_actions.delete_at(i)
        return action
      end
    end

    nil
  end

  def extract_semver_actions(actions)
    semver_actions = []
    other_actions = []

    actions.each do |action|
      if semver = @semver_parser.parse(action.ref)
        semver_actions << UnclassifiedSemverAction.new(
          requested_nwo: action.requested_nwo,
          processed_nwo: action.processed_nwo,
          ref: action.ref,
          normalised_semver: semver)
      else
        other_actions << action
      end
    end

    [semver_actions, other_actions]
  end
end
