# typed: strict
# frozen_string_literal: true

class Copilot::TelemetrySnapshot
  extend T::Helpers
  extend T::Sig
  include GitHub::Memoizer

  sig { returns(Symbol) }
  attr_reader :access_type

  sig { returns(T::Array[Copilot::Business]) }
  attr_reader :businesses

  sig { returns(T::Array[Integer]) }
  attr_reader :enterprise_team_ids

  sig { returns(T::Array[Copilot::Organization]) }
  attr_reader :organizations

  sig { returns(String) }
  attr_reader :source

  sig { returns(T::Array[::Team]) }
  attr_reader :teams

  sig { returns T.nilable(String) }
  attr_reader :telemetry_snapshot_id

  sig { returns(T::Hash[String, T.any(String, Symbol)]) }
  attr_reader :telemetry_snapshot_metadata

  sig { returns(Copilot::User) }
  attr_reader :copilot_user

  sig { returns(Integer) }
  attr_reader :user_id

  sig { params(copilot_user: Copilot::User, source: String).void }
  def initialize(copilot_user, source: "token_endpoint")
    # so, if the user has no access or is CFI, this doesn't exist
    return unless copilot_user.access_allowed?
    return if copilot_user.has_cfi_access?

    @copilot_user = T.let(copilot_user, Copilot::User)
    @user         = T.let(copilot_user.user_object, ::User)
    @source       = T.let(source, String)

    @user_id = T.let(copilot_user.id, Integer)

    # calling this makes the teams and businesses and organizations available
    @access_type = T.let(copilot_user.copilot_authorizer_object.access_type, Symbol)

    # this needs to be only teams that this user is a member of that have at least 5 Copilot seated users
    # https://github.com/github/heart-services/issues/4554 is when we will implement this so it will
    # temporarily be empty
    @teams = T.let(
      [],
      T::Array[::Team]
    )

    # these are all based off of Copilot Seats and SeatAssignments
    @businesses = T.let(
      copilot_user.copilot_businesses,
      T::Array[Copilot::Business],
    )

    @organizations = T.let(
      copilot_user.copilot_organizations,
      T::Array[Copilot::Organization],
    )

    @enterprise_team_ids = T.let(
      copilot_user.enterprise_team_ids,
      T::Array[Integer],
    )

    # this is blank for now
    @telemetry_snapshot_metadata = T.let({}, T::Hash[String, T.any(String, Symbol)])
    @telemetry_snapshot_id = T.let(unique_value, T.nilable(String))
  end

  private

  # # create a string from the values and hash it so that we can compare the string to something stored
  sig { returns(String) }
  memoize def unique_value
    vals = []
    vals << "u:#{@user.id}"
    vals << "a:#{@access_type}"
    vals << "s:#{@source}"
    vals << "t:#{@teams.map(&:id).sort.join(",")}"
    vals << "e:#{@businesses.map(&:id).sort.join(",")}"
    vals << "o:#{@organizations.map(&:id).sort.join(",")}"
    vals << "et:#{@enterprise_team_ids.sort.join(",")}"

    "ts-#{Digest::SHA256.hexdigest(vals.join("|"))}"
  end
end
