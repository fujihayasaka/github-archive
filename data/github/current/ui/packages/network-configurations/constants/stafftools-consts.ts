export const StafftoolsConsts = {
  stafftoolsEnterpriseLink: (slug: string): string => `/stafftools/enterprises/${slug}/hosted_compute_networking`,
  stafftoolsEnterprisePrivateNetworksLink: (slug: string, id: string): string =>
    `/stafftools/enterprises/${slug}/hosted_compute_networking/${id}`,
  stafftoolsUserLink: (userId: string): string => `/stafftools/users/${userId}/hosted_compute_networking`,
  stafftoolsUserPrivateNetworksLink: (userId: string, id: string) =>
    `/stafftools/users/${userId}/hosted_compute_networking/${id}`,
}
