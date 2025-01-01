import {StafftoolsConsts} from '../constants/stafftools-consts'

export function staffToolsNetworkConfigurationLink(isEnterprise: boolean, actor: string) {
  return isEnterprise ? StafftoolsConsts.stafftoolsEnterpriseLink(actor) : StafftoolsConsts.stafftoolsUserLink(actor)
}

export function staffToolsPrivateNetworksLink(isEnterprise: boolean, actor: string, id: string) {
  return isEnterprise
    ? StafftoolsConsts.stafftoolsEnterprisePrivateNetworksLink(actor, id)
    : StafftoolsConsts.stafftoolsUserPrivateNetworksLink(actor, id)
}
