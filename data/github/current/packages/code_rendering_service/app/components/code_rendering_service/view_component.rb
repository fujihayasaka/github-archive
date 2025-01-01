# typed: true
# frozen_string_literal: true

module CodeRenderingService
  class ViewComponent < CodeRenderingService::BaseComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    include Scientist

    # Template context aware url generator. Uses the template helper to see if the commit_sha is
    # setup upstream of the component creation
    def iframe_url
      # XXX: When showing a list of snippets, a specific revision cannot be
      # specified. Fall back to the blobs latest sha.
      safe_commit_oid = helpers.respond_to?(:commit_sha) ? helpers.commit_sha : blob.repository.ref_to_sha(blob.repository.default_branch)
      url_for_display(commit_oid: safe_commit_oid)
    end

    # Return a viewscreen url for displaying the requested content.
    # params:
    # commit_oid: Blobs sha
    # Returns - String url to use when passing the encoded urls for the codeload resources to be rendered
    #           by the code rendering service
    #      Get Params:
    #         color_mode: The users selected color mode
    #         enc_url: The hash encoded url to file
    #         path: file path to the blob
    #         repository_id: database id of the repository
    #         repository_type: Gist or Repository
    #         logged_in: state of the user
    #         nwo: Repository name with owner
    #         commit: the commit sha of the latest change
    #         browser: the users browser
    #         version: the users browser version
    #
    def url_for_display(commit_oid: nil)
      return unless supports_view?
      return unless render_type

      repository = blob.repository
      path = blob.path
      content_url = generate_codeload_url(repository, path, commit_oid, blob.git_lfs_pointer)

      query = {
        enc_url: encode_url(content_url),
        path: path,
        commit: commit_oid,
        nwo: blob.repository.name_with_display_owner,
        repository_id: blob.repository.id,
        repository_type: blob.repository.class.name,
        color_mode: color_mode,
        logged_in: logged_in?,
        docs_host: GitHub.help_url,
      }.merge(useragent_to_h)

      if bypass_fastly?(blob.repository)
        query["bypass_fastly"] = true
      end

      if link_underlines_enabled?
        query["link_underline_enabled"] = true
      end

      URI.parse([
        host_url,
        "view",
        "#{render_type}?#{query.to_param}"
      ].compact.join("/"))
    end
  end
end
