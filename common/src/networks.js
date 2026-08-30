import { deployments } from '@erc-8270/contracts';

export const NETWORK = {
    id: "gnosis",
    chainId: 100,
    name: "Gnosis Chain",
    isGno: true,
    currency: "GNO",
    rpcUrl: "https://rpc.gnosischain.com",
    beaconApiUrl: "https://gnosis.beaconrpc.bbjubjub.fr",
    explorerUrl: "https://gnosisscan.io",
    mainAddress: deployments[100]?.ERC8270,
    depositsAddress: deployments[100]?.DepositsGno,
    depositsContractAddress: "0x0B98057eA310F4d31F2a452B414647007d1645d9",
    gnoTokenAddress: "0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb",
};