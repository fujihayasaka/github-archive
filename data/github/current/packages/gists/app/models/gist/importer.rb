# typed: false
# frozen_string_literal: true

require "open-uri"

# Used to import production Gists to development for testing.
#
# Usage:
#   Gist::Importer.import "ed298310dd7a92f10ff0", the("defunkt")
#
# Note: If you don't supply the user, it will create one based
#       off the user in the Gist data.
class Gist::Importer

  # Import Gist from production.
  #
  # gist_id - The id of the Gist.
  # user    - The user to assign to this Gist.
  #
  # Returns a Gist.
  def self.import(gist_id, user = nil)
    create_gist Octokit.gist(gist_id), user
  end

  # Private: Create a Gist from an API response
  #
  # data - The gist Hash of attributes from API
  # user    - The user to assign to this Gist.
  #
  # Returns a new Gist object imported from production.
  def self.create_gist(data, user)
    if gist = Gist.find_by_repo_name(data["id"])
      gist.remove(async: false)
    end

    user ||= if user_data = data["user"]
      User.find_by_login(user_data["login"])
    end

    gist_creator = Gist::Creator.new \
      repo_name: data["id"],
      user: user,
      public: data["public"],
      description: data["description"],
      contents: file_params_to_contents(data["files"]),
      created_at: data["created_at"],
      updated_at: data["updated_at"]

    if gist_creator.create
      Octokit.gist_comments(data["id"]).each do |comment|
        import_gist_comment(gist_creator.gist, comment, user)
      end
    else
      raise gist_creator.gist.errors.inspect
    end

    gist_creator.gist
  end

  def self.import_gist_comment(gist, comment, user)
    new_comment = gist.comments.new
    new_comment.created_at = comment["created_at"]
    new_comment.updated_at = comment["updated_at"]
    new_comment.body = comment["body"]
    new_comment.user = user
    new_comment.save!
  end

  # Private: Convert the file params to a contents hash
  #
  # files - The files hash from the API
  #
  # Returns a Hash of { "file_name" => "contents" }
  def self.file_params_to_contents(files)
    contents = []
    files.to_hash.each do |name, file_info|
      contents << { name: name.to_s, value: file_info["content"] }
    end
    contents
  end
end
