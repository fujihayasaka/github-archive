# typed: false
# frozen_string_literal: true

class Stafftools::StorageController < StafftoolsController
  before_action :ensure_cluster_enabled
  before_action :redirect_to_blob, only: [:index, :blobs]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:blob]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:blobs]

  def index
    @fileservers = ::Storage::FileServer.all
    @partitions = ::Storage::Partition.total_for(@fileservers)
    @media_blobs = media_blobs

    render "stafftools/storage/index"
  end

  def blobs # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/storage/blobs"
  end

  def blob # rubocop:todo GitHub/UseRestfulActions
    if @blob = ::Storage::Blob.find_by_oid(params[:oid])
      render "stafftools/storage/blob"
    else
      flash[:notice] = "No object found"
      redirect_to stafftools_storage_blobs_path
    end
  end

  private

  def media_blobs
    Media::Blob.includes({ repository_network: { root: [:owner] } })
      .select("sum(size) as total_size, repository_network_id, media_blobs.id")
      .joins("JOIN repository_networks ON repository_network_id = repository_networks.id")
      .group("repository_network_id")
      .order(Arel.sql("sum(size) DESC"))
      .limit(20)
      .reject { |b| b.repository_network.root.owner.nil? }
  end

  def redirect_to_blob
    oid = params[:oid]
    redirect_to stafftools_storage_blob_path(oid) unless oid.blank?
  end

  def ensure_cluster_enabled
    render_404 unless GitHub.storage_cluster_enabled?
  end
end
