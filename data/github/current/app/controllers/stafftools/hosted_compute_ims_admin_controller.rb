# typed: false
# frozen_string_literal: true

class Stafftools::HostedComputeImsAdminController < StafftoolsController
  extend T::Sig

  include ReactHelper

  before_action :dotcom_required # limiting to dotcom so only GitHub staff can access
  before_action :ims_stafftools_enabled

  sig { returns(String) }
  def self.react_bundle_name
    "hosted-compute-ims-stafftools"
  end

  def index
    # IMS is a new service and we don't have real API calls to it.
    # This stafftools controller and UI is used for testing integration between dotcom and IMS
    # So, hardcode our test org "bbq-beets" for now because "current_user.organizations.first" seems to be too unpredictable
    current_org = Organization.find_by_login("bbq-beets")
    unless current_org.present?
      current_org = current_user.organizations.first
    end
    return redirect_to "/" unless current_org.present?

    image_definitions_error = nil
    image_versions_error = nil


    pointers = [
      {
        id: "951",
        name: "2024061000154375603-uploading-def-1-1",
        os_type: "Windows",
        architecture: "Arm64",
        enabled: true,
        points_to_image_definition_id: "4",
        created_at: "2024-06-10T00:15:43.796704Z",
        updated_at: "2024-06-10T00:36:08.453472Z"
      },
      {
        id: "952",
        name: "2024061000154375604-uploading-def-0-1",
        os_type: "Linux",
        architecture: "Arm64",
        enabled: true,
        points_to_image_definition_id: "5",
        created_at: "2024-06-10T00:15:43.795887Z",
        updated_at: "2024-06-10T00:28:27.666730Z"
      },
      {
        id: "953",
        name: "2024061000154375607-def-0",
        os_type: "Linux",
        architecture: "X64",
        enabled: true,
        points_to_image_definition_id: "6",
        created_at: "2024-06-10T00:15:43.803479Z",
        updated_at: "2024-06-10T00:15:44.551202Z"
      }
    ]

    image_definitions = [
      {
        id: "1654",
        name: "2024061000154375603-uploading-def-1-1",
        os_type: "Windows",
        architecture: "Arm64",
        enabled: true,
        points_to_image_definition_id: "0",
        created_at: "2024-06-10T00:15:43.796704Z",
        updated_at: "2024-06-10T00:36:08.453472Z"
      },
      {
        id: "1653",
        name: "2024061000154375604-uploading-def-0-1",
        os_type: "Linux",
        architecture: "Arm64",
        enabled: true,
        points_to_image_definition_id: "0",
        created_at: "2024-06-10T00:15:43.795887Z",
        updated_at: "2024-06-10T00:28:27.666730Z"
      },
      {
        id: "1652",
        name: "2024061000154375607-def-0",
        os_type: "Linux",
        architecture: "X64",
        enabled: true,
        points_to_image_definition_id: "0",
        created_at: "2024-06-10T00:15:43.803479Z",
        updated_at: "2024-06-10T00:15:44.551202Z"
      }
    ]

    image_versions = [
      {
        image_definition_id: "1654",
        version: "20240724.0.1",
        state: "Ready",
        state_details: "",
        size_gb: 75,
        enabled: true,
        created_at: "2024-06-10T00:15:43.803479Z",
        updated_at: "2024-06-10T00:15:44.551202Z"
      },
      {
        image_definition_id: "1654",
        version: "20240724.0.2",
        state: "Ready",
        state_details: "",
        size_gb: 75,
        enabled: true,
        created_at: "2024-06-10T00:15:43.803479Z",
        updated_at: "2024-06-10T00:15:44.551202Z"
      },
      {
        image_definition_id: "1653",
        version: "20240724.0.2",
        state: "Ready",
        state_details: "",
        size_gb: 75,
        enabled: true,
        created_at: "2024-06-10T00:15:43.803479Z",
        updated_at: "2024-06-10T00:15:44.551202Z"
      }
    ]
    merged_image_definition_and_image_versions_list = merge_image_definitions_and_versions(image_definitions, image_versions)

    render_react_app(
      payload: {
        imageDefinitionPointers: pointers.map(&method(:convert_image_definition_to_react_payload)),
        imageDefinitions: merged_image_definition_and_image_versions_list.map(&method(:convert_image_definition_to_react_payload)),
        imsStafftoolsPath: stafftools_hosted_compute_ims_admin_index_path,
        newCuratedImagePath: stafftools_hosted_compute_ims_admin_new_image_definiton_path,
        newCuratedPointerPath: stafftools_hosted_compute_ims_admin_new_pointer_path
      },
      title: "HostedComputeImsAdminStafftools",
      layout: "layouts/stafftools/react_stafftools",
      ssr: true
    )
  end

  def new_curated_image # rubocop:todo GitHub/UseRestfulActions
    render_react_app(
      payload: {
        imsStafftoolsPath: stafftools_hosted_compute_ims_admin_index_path
      },
      title: "HostedComputeImsAdminStafftools",
      layout: "layouts/stafftools/react_stafftools",
      ssr: true
    )
  end

  def new_curated_pointer # rubocop:todo GitHub/UseRestfulActions
    render_react_app(
      payload: {
        imsStafftoolsPath: stafftools_hosted_compute_ims_admin_index_path
      },
      title: "HostedComputeImsAdminStafftools",
      layout: "layouts/stafftools/react_stafftools",
      ssr: true
    )
  end

  def create
    current_org = current_user.organizations.first
    return redirect_to "/" unless current_org.present?

    image_definition_resp = ims_client.create_customer_image_definition(current_org, name: params[:name], os_type: params[:os_type], architecture: params[:architecture])

    unless image_definition_resp.call_succeeded
      render_react_app(
        payload: {
          title: "New"
        },
        title: "HostedComputeImsAdminStafftools",
        layout: "layouts/stafftools/react_stafftools",
        ssr: true
      )
    end

    image_version_resp = ims_client.create_customer_image_version(current_org, image_definition_id: image_definition_resp.value.image_definition.id, version: params[:version], source_vhd_url: params[:source_vhd_url])

    unless image_version_resp.call_succeeded
      render_react_app(
        payload: {
          title: "New"
        },
        title: "HostedComputeImsAdminStafftools",
        layout: "layouts/stafftools/react_stafftools",
        ssr: true
      )
    end

    redirect_to :stafftools_hosted_compute_ims_admin_index
  end

  def show
    image_definition = {
      id: "1654",
      name: "2024061000154375603-uploading-def-1-1",
      os_type: "Windows",
      architecture: "Arm64",
      enabled: true,
      points_to_image_definition_id: "0",
      created_at: "2024-06-10T00:15:43.796704Z",
      updated_at: "2024-06-10T00:36:08.453472Z"
    }
    image_versions = [
      {
        image_definition_id: "1654",
        version: "20240724.0.1",
        state: "Ready",
        state_details: "",
        size_gb: 75,
        enabled: true,
        created_at: "2024-06-10T00:15:43.803479Z",
        updated_at: "2024-06-10T00:15:44.551202Z"
      },
      {
        image_definition_id: "1654",
        version: "20240724.0.2",
        state: "Ready",
        state_details: "really really long data .................",
        size_gb: 75,
        enabled: true,
        created_at: "2024-06-10T00:15:43.803479Z",
        updated_at: "2024-06-10T00:15:44.551202Z"
      }
    ]
    render_react_app(
      payload: {
        imageDefinition: convert_image_definition_to_react_payload(image_definition),
        imageVersions: image_versions.map(&method(:convert_image_version_to_react_payload)),
        imsStafftoolsPath: stafftools_hosted_compute_ims_admin_index_path,
      },
      title: "Image Version List",
      layout: "layouts/stafftools/react_stafftools",
      ssr: true
    )
  end

  private

  memoize def ims_client
    ::HostedComputeIms::Twirp::ImagesClient.new(base_url: GitHub.hosted_compute_ims_production_url, hmac_key: GitHub.hosted_compute_ims_hmac_key)
  end

  memoize def ims_admin_client
    ::HostedComputeIms::Twirp::AdminClient.new(base_url: GitHub.hosted_compute_ims_production_url, hmac_key: GitHub.hosted_compute_ims_hmac_key)
  end

  def convert_image_definition_to_react_payload(object)
    {
      id: object[:id],
      name: object[:name],
      osType: object[:os_type],
      architecture: object[:architecture],
      enabled: object[:enabled],
      pointsToImageDefinitionId: object[:points_to_image_definition_id],
      createdAt: object[:created_at],
      updatedAt: object[:updated_at],
      imageVersionsCount: (object[:image_versions] || []).size
    }
  end

  def convert_image_version_to_react_payload(object)
    {
      imageDefinitionId: object[:image_definition_id],
      version: object[:version],
      state: object[:state],
      stateDetails: object[:state_details],
      sizeGb: object[:size_gb],
      enabled: object[:enabled],
      createdAt: object[:created_at],
      updatedAt: object[:created_at],
    }
  end

  def merge_image_definitions_and_versions(image_definitions, image_versions)
    # Create a hash map for image definitions
    image_definitions_map = image_definitions.each_with_object({}) do |image_def, map|
      map[image_def[:id]] = image_def.merge(image_versions: [])
    end

    # Add image versions to the corresponding image definitions
    image_versions.each do |version|
      image_def_id = version[:image_definition_id]
      if image_definitions_map.key?(image_def_id)
        image_definitions_map[image_def_id][:image_versions] << version
      end
    end

    # Convert the hash map values back to a list
    image_definitions_map.values
  end

  def ims_stafftools_enabled
    render_404 unless GitHub.flipper[:hosted_compute_ims_stafftools].enabled?(current_user)
  end
end
