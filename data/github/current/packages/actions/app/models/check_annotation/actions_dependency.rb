# typed: false
# frozen_string_literal: true

# Actions-specific functionality for check annotations (AKA workflow runs)

module CheckAnnotation::ActionsDependency

  # Public: Accepts a required workflow file path along with the metadata
  # and returns the file path of the workflow file present in
  # the source repo along with the repo's nwo
  def parse_and_format_required_workflow_filename
    split_name = filename.split("/")
    source_repo_id = split_name[1]

    split_name.slice!(0..1)

    source_repo = Repository.find_by(id: source_repo_id)
    return filename if source_repo.nil?

    [source_repo.nwo, split_name].join("/")
  end
end
