# typed: true
# frozen_string_literal: true

class Api::UserFollowers < Api::App
  include ReceiveSchemaWithOpenApi

  # List a User's followers
  get "/user/:user_id/followers", operation_id: "users/list-followers-for-user" do
    user = find_user!
    control_access :read_user_public,
      resource: Platform::PublicResource.new(resource: user),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Count without the join to users if possible
    pagination_opts = pagination.update(total_entries: user.followers_count_for_viewer(current_user))
    users = user.followers_for_viewer(current_user).paginate(pagination_opts)

    deliver :user_hash, users
  end

  # List the authenticated User's followers
  get "/user/followers", operation_id: "users/list-followers-for-authenticated-user" do
    control_access :read_user_followers,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    # Count without the join to users if possible
    pagination_opts = pagination.update(total_entries: current_user.followers_count_for_viewer(current_user))
    users = current_user.followers_for_viewer(current_user).paginate(pagination_opts)

    deliver :user_hash, users
  end

  # List who a User is following
  get "/user/:user_id/following", operation_id: "users/list-following-for-user" do
    user = find_user!
    control_access :read_user_public,
      resource: Platform::PublicResource.new(resource: user),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Count without the join to users if possible
    pagination_opts = pagination.update(total_entries: user.following_count_for_viewer(current_user))
    users = user.following_for_viewer(current_user).paginate(pagination_opts)

    deliver :user_hash, users
  end

  # List users the authenticated User is following
  get "/user/following", operation_id: "users/list-followed-by-authenticated-user" do
    control_access :read_user_following,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    # Count without the join to users if possible
    pagination_opts = pagination.update(total_entries: current_user.following_count_for_viewer(current_user))
    users = current_user.following_for_viewer(current_user).paginate(pagination_opts)

    deliver :user_hash, users
  end

  # Get if the authenticated User is following a User
  get "/user/following/:username", operation_id: "users/check-person-is-followed-by-authenticated" do
    control_access :read_user_following,
      resource: this_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    other_user = this_user

    if !other_user.spammy? && other_user.followed_by?(current_user)
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  # Check if a user is following another user
  get "/user/:user_id/following/:target_user", operation_id: "users/check-following-for-user" do
    user = find_user!

    control_access :read_user_public,
      resource: Platform::PublicResource.new(resource: user),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    target_user = User.find_by_login(params[:target_user])

    if !target_user ||
      (user.spammy? && user != current_user) ||
      (target_user.spammy? && target_user != current_user) ||
      !target_user.followed_by?(user)

      deliver_error 404
    else
      deliver_empty(status: 204)
    end
  end

  # Follow a User
  put "/user/following/:username", operation_id: "users/follow" do
    # Introducing strict validation of the user.follow
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("user", "follow", skip_validation: true)

    control_access :follow,
      resource: this_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    following = Following.new(user: current_user, following: this_user)
    if following.creation_rate_limited?
      deliver_error! 429,
        message: "You can't perform that action at this time",
        errors: [api_error(:User, :following, :invalid, value: "rate limit exceeded")]
    else
      current_user.follow(this_user, context: "api")
      deliver_empty(status: 204)
    end
  end

  # Unfollow a User
  delete "/user/following/:username", operation_id: "users/unfollow" do
    receive_with_schema("user", "unfollow")

    control_access :unfollow,
      resource: this_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    current_user.unfollow(this_user, context: "api")

    deliver_empty(status: 204)
  end
end
