# typed: false
# frozen_string_literal: true

module Stafftools
  class StorageBlobView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :blob

    def references
      @references ||= @blob.storage_references.limit(100)
    end

    def each_reference_link(&block)
      refs_by_type = references.group_by { |r| r.uploadable_type.to_s.underscore.gsub("/", "_") }
      refs_by_type.each do |type_name, refs|
        next if refs.blank?

        type_method = "show_#{type_name}_references"
        if respond_to?(type_method, true)
          send(type_method, refs, &block)
        else
          show_unknown_references(type_name, refs, &block)
        end
      end
    end

    private

    def link_to_storage_object
      urls.stafftools_storage_blob_path(@blob.oid)
    end

    def link_to_ref(title, url = nil)
      if url
        helpers.link_to(title, url)
      else
        title
      end
    end

    def show_avatar_references(refs, &block)
      avatars = ::Avatar.where(id: refs.map(&:uploadable_id)).index_by(&:id)
      users = ::User.where(id: avatars.values.map(&:uploader_id).uniq).index_by(&:id)
      refs.each do |ref|
        avatar = avatars[ref.uploadable_id]
        uploader = users[avatar.uploader_id] if avatar
        text = uploader ? "Avatar uploaded by #{uploader}" : "Avatar ##{ref.uploadable_id}"
        block.call link_to_ref(text, urls.stafftools_user_avatars_path(uploader))
      end
    end

    def show_media_blob_references(refs, &block)
      blobs = ::Media::Blob.where(id: refs.map(&:uploadable_id))
      networks = ::RepositoryNetwork.where(id: blobs.map(&:repository_network_id).uniq).index_by(&:id)
      repos = ::Repository.includes(:owner).where(id: networks.values.map(&:root_id).uniq).index_by(&:id)
      blobs.each do |b|
        network = networks[b.repository_network_id]
        repo = repos[network.root_id] if network
        if repo
          block.call link_to_ref("Git LFS object in #{repo.name_with_owner} (#{repo.public? ? :public : :private})", urls.gh_stafftools_repository_large_files_path(repo, oid: b.oid))
        else
          block.call link_to_ref("Git LFS object in <unknown>")
        end
      end
    end

    def show_release_asset_references(refs, &block)
      relfiles = Releases::Public.load_assets(refs.map(&:uploadable_id))
      rels = Releases::Public.load_releases(relfiles.map(&:release_id).uniq).index_by(&:id)
      repos = ::Repository.where(id: relfiles.map(&:repository_id).uniq).index_by(&:id)
      relfiles.each do |relfile|
        rel = rels[relfile.release_id]
        repo = repos[relfile.repository_id]
        if rel && repo
          block.call link_to_ref("Release file #{relfile.name.inspect} for the #{rel.name.inspect} tag in #{repo.name_with_owner}")
        else
          block.call link_to_ref("Release file in <unknown>")
        end
      end
    end

    def show_repository_file_references(refs, &block)
      repofiles = ::RepositoryFile.where(id: refs.map(&:uploadable_id))
      repos = ::Repository.where(id: repofiles.map(&:repository_id).uniq).index_by(&:id)
      repofiles.each do |repofile|
        repo = repos[repofile.repository_id]
        if repo
          block.call link_to_ref("Repository file #{repofile.name.inspect} in #{repo.name_with_owner}")
        else
          block.call link_to_ref("Repository file in <unknown>")
        end
      end
    end

    def show_oauth_application_logo_references(refs, &block)
      if refs.size == 1
        block.call link_to_ref("OAuth Application Logo")
      else
        block.call link_to_ref("#{refs.size} OAuth Application Logos")
      end
    end

    def show_user_asset_references(refs, &block)
      if refs.size == 1
        block.call link_to_ref("Issue image upload")
      else
        block.call link_to_ref("#{refs.size} Issue image uploads")
      end
    end

    def show_unknown_references(type_name, refs, &block)
      refs.each do |ref|
        block.call link_to_ref("#{type_name} ##{ref.uploadable_id}")
      end
    end
  end
end
