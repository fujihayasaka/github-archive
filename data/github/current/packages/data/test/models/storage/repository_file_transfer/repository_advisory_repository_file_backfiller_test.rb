# typed: true
# frozen_string_literal: true

require "test_helper"


class StorageRepositoryAdvisoryRepositoryFileBackfillerTest < GitHub::TestCase
  skip_enterprise
  skip_in_multitenant_mode

  fixtures do
    @user = create(:user)
    @repo = create :public_repository, owner: @user
  end

  def with_repository_advisory(user, external_files: nil, upload_container: nil, update_upload_container_id: false)
    GitHub.context.push(actor_id: user.id)

    args = { uploader: user }
    args.merge!(upload_container ? { upload_container: upload_container } : { upload_container_type: RepositoryAdvisory.name })

    repository_files = external_files ? external_files : create_list(:repository_file, 2, args)
    urls = repository_files.map { |repository_file| "#{GitHub.url}/user-attachments/files/#{repository_file.id}/#{repository_file.name}" }
    description = urls.map { |url| url }.join("\n")
    advisory = create(:repository_advisory, repository: @repo, author: user, state: "open", description: description)

    RepositoryFile.where(id: repository_files.map(&:id)).update_all(upload_container_id: advisory.id) if update_upload_container_id

    yield(repository_files, advisory)
  end

  context "#backfill_upload_container_ids" do
    test "backfills upload_container_id if actor is owner of repository files" do
      with_repository_advisory(@user) do |repository_files, repository_advisory|
        repository_files.each do |repository_file|
          repository_file.reload
          assert_equal repository_advisory.id, repository_file.upload_container_id
        end
      end
    end

    test "doesn't backfill upload_container_id if the actor is not the owner of the repository files" do
      file_owner = create(:user)
      files = create_list(:repository_file, 2, uploader: file_owner)
      with_repository_advisory(@user, external_files: files) do |files, _|
        files.each do |file|
          file.reload
          assert_nil file.upload_container_type
          assert_nil file.upload_container_id
        end
      end
    end

    test "doesn't backfill upload_container_id if the actor is not the owner of the repository files in another advisory" do
      file_owner = create(:user)
      with_repository_advisory(file_owner) do |other_repo_files, other_user_advisory|
        other_repo_files.each do |file|
          # Ensure that upload_container_id is set for these models.
          file.reload
        end
        with_repository_advisory(@user, external_files: other_repo_files) do |files, advisory|
          files.each do |file|
            file.reload
            assert_equal RepositoryAdvisory.name, file.upload_container_type
            refute_equal advisory.id, file.upload_container_id
            assert_equal other_user_advisory.id, file.upload_container_id
          end
        end
      end
    end

    test "doesn't backfill upload_container_id if repository file already belongs to a given RepositoryAdvisory" do
      with_repository_advisory(@user, update_upload_container_id: true) do |repository_files, repository_advisory|
        urls = repository_files.map { |repository_file| "#{GitHub.url}/user-attachments/files/#{repository_file.id}/#{repository_file.name}" }
        description = urls.map { |url| url }.join("\n")
        repository_advisory_new = create(:repository_advisory, repository: @repo, author: @user, state: "open", description: description)
        repository_files.each do |repository_file|
          repository_file.reload
          refute_equal repository_advisory_new.id, repository_file.upload_container_id
          assert_equal repository_advisory.id, repository_file.upload_container_id
        end
      end
    end

    test "doesn't backfill upload_container_id if upload_container is not a RepositoryAdvisory" do
      repo = create(:repository)
      with_repository_advisory(@user, upload_container: repo) do |files, _|
        files.each do |file|
          file.reload
          assert_equal repo, file.upload_container
        end
      end
    end
  end
end
