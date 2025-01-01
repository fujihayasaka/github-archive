# typed: true
# frozen_string_literal: true

class RepositoryAdvisory::Loader::AdvisoryComments < Issue::Loader::Base
  include Issue::PrefillHelper

  def initialize(context)
    @repository = context.repository
    @viewer = context.viewer
    @context = context
  end

  def preload(advisory_comments)
    models = advisory_comments

    GitHub::PrefillAssociations.prefill_batch_method(models, :prelude_viewer_can_react, @viewer)
    GitHub::PrefillAssociations.prefill_batch_method(models, :prelude_user_logins_by_reaction)

    promises = [
      async_preload_attribute(models, :viewer_can_update, :async_viewer_can_update?, [@viewer]),
      async_preload_attribute(models, :viewer_can_react, :async_viewer_can_react?, [@viewer]),
      async_preload_attribute(models,
                              :body_html,
                              :async_body_html,
                              [],
                              {
                                context: {
                                  viewer: @viewer,
                                  unfurl_references: true,
                                  cap_filter: @context.cap_filter
                                }
                              }),
      async_preload_attribute(models, :readable_by, :async_readable_by?, [@viewer]),
      async_preload_attribute(models, :viewer_can_read_user_content_edits, :async_viewer_can_read_user_content_edits?, [@viewer]),
      async_preload_attribute(models, :reaction_groups, :async_reaction_groups),
      async_preload_attribute(models, :reaction_path, :async_reaction_path),
      async_preload_attribute(models, :user_is_spammy, :async_user_is_spammy, [@viewer])
    ]

    Promise.all(promises).sync

    Issue::Loader::CurrentRepository.load_for(@context)

    reaction_groups = Issue::Loader::ReactionGroups.load_for(
      @context,
      reaction_groups: models.map(&:reaction_groups).flatten
    )

    # preload the users and the avatars
    # filter models by has author_id
    author_models = models.filter { |m| m.is_a?(RepositoryAdvisory) }
    user_models = models.filter { |m| !m.is_a?(RepositoryAdvisory) } # user

    user_ids = (
      author_models.map(&:author_id) +
      user_models.map(&:user_id) +
      reaction_groups.map(&:user_ids).flatten
    ).compact.uniq


    # all users and authors
    user_loader = Issue::Loader::Users.new(@context, user_ids: user_ids)
    user_loader.load
    user_loader.preload_primary_avatars_for_users(@context.users, "users")

    # prefill author
    prefill_from_exhaustive_available_records(author_models, :author, available_records: @context.users)
    prefill_from_exhaustive_available_records(user_models, :user, available_records: @context.users)

    # set the author associations
    author_associations_loader = Issue::Loader::CommentAuthorAssociations.load_for(@context, associables: models)

    # prefill the editor
    latest_user_content_edits = models.map(&:latest_user_content_edit)
    prefill_from_exhaustive_available_records(latest_user_content_edits, :editor, available_records: @context.users)
  end
end
