# typed: true
# frozen_string_literal: true

class CommitBadgesController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:index]

  VERIFYABLE_TYPE_NAMES = %w(Commit Tag)
  ALLOWED_RENDER_LOCALS = %w(badge_size dropdown_direction)

  # params[:items] = {
  #   item-0: { id: COMMIT_OR_TAG_GLOBAL_RELAY_ID, badge_size: "small", dropdown_direction: "s" },
  #   item-1: { id: COMMIT_OR_TAG_GLOBAL_RELAY_ID, badge_size: "small", dropdown_direction: "s" },
  #   …
  # }
  def index
    inputs = params.require(:items).permit!.to_h
    keyed_contents = ActiveRecord::Base.connected_to(role: :reading) do
      keyed_objects = load_objects_from_inputs(inputs)
      keyed_objects.each_with_object({}) do |(key, commit_or_tag), contents|
        contents[key] = render_badge(commit_or_tag, locals: inputs[key].slice(*ALLOWED_RENDER_LOCALS))
      end
    end

    respond_to do |wants|
      wants.json do
        render json: keyed_contents
      end
    end
  rescue ActionController::ParameterMissing
    head :bad_request
  end

  private

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:todo GitHub/SpecifyTargetForConditionalAccess
  end

  def load_objects_from_inputs(inputs)
    object_promises = inputs.filter_map do |(key, item)|
      global_id = item["id"]

      begin
        type_name, id = Platform::Helpers::NodeIdentification.from_global_id(global_id)
      rescue Platform::Errors::NotFound
        GitHub.logger.info(
          "Unresolvable global id encountered",
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.graphql.global_id" => global_id,
          "gh.request_id" => GitHub.context[:request_id],
          "gh.catalog_service" => "github/repos"
        )
        next
      end

      next Promise.resolve([key, nil]) unless VERIFYABLE_TYPE_NAMES.include?(type_name)

      if Platform::Helpers::GlobalId.next?(global_id)
        next_global_id = Platform::Helpers::GlobalId.parse(global_id)
        Platform::Interfaces::GitObject.load_from_next_global_id(next_global_id).then do |git_object|
          [key, git_object]
        end
      else
        Platform::Interfaces::GitObject.load_from_global_id(id).then do |git_object|
          [key, git_object]
        end
      end
    end

    objects_by_key = Platform::Security::RepositoryAccess.with_viewer(current_user) do
      Promise.all(object_promises).sync.to_h
    end

    commits, tags = objects_by_key.values.compact.partition { |obj| obj.is_a?(Commit) }

    # Preload signatures and verification status. Signatures for commits and tags must
    # be initiated on separate lines to avoid GitSigning::NPlusOne from throwing an exception.
    Promise.all(commits.map(&:async_signature)).sync if commits.any?
    Promise.all(tags.map(&:async_signature)).sync if tags.any?
    Promise.all((commits + tags).map(&:async_verification_status)).sync

    objects_by_key
  end

  def render_badge(commit_or_tag, locals: {})
    return "" unless commit_or_tag

    # Rubocop really doesn't like this line even though we use
    # a string literal for `partial` and we use `render_to_string`
    # elsewhere with no issues.
    #
    # rubocop:disable GitHub/RailsControllerRenderLiteral
    render_to_string(
      partial: "commits/signed_commit_badge",
      formats: [:html],
      locals: locals.merge({
        item: commit_or_tag,
        verification_status: commit_or_tag.verification_status
      })
    )
  end

end
