# typed: true
# frozen_string_literal: true

module Gists
  # Controls the gist new/create view
  # eg https://github.com/gists/
  class NewPageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

    attr_reader :gist, :max_recent

    delegate :description, to: :gist

    def page_class
      "page-gist-edit"
    end

    def page_title
      "Create a new Gist"
    end

    def allow_contents_unchanged
      true
    end

    def default_filename
      "gistfile1.txt"
    end

    def new_file?
      true
    end

    # What objects does the form_for tag operate on?
    def form_objects
      gist
    end

    # Used for submit buttons on New/Edit
    def visibility_text
      gist.public? ? public_gist_label : "secret"
    end

    def public_gist_label
      "public"
    end

    def public_gist_description
      "Public gists are visible to everyone."
    end

    def has_recent_gists?
      recent_gists.present?
    end

    def recent_gists
      @recent_gists ||= if logged_in?
        current_user.gists.active.limit(max_recent).order("pushed_at DESC")
      else
        []
      end
    end

    def viewer_must_verify_email?
      logged_in? && current_user.must_verify_email?
    end

    def files_for_view
      files = gist.files_for_view.to_a
      # [file_name, contents, oid, and blob]
      files.present? ? files : [[nil, nil, nil, nil]]
    end
  end
end
