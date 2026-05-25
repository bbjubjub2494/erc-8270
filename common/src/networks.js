import { deployments } from '@erc-8270/contracts';

export const NETWORKS = {
    chiado: {
	id: "chiado",
	chainId: 10200,
	name: "Chiado",
	isGno: true,
	currency: "GNO",
	rpcUrl: "https://chiado.rpc.bbjubjub.fr",
	beaconApiUrl: "https://chiado.beaconrpc.bbjubjub.fr",
	explorerUrl: "https://chiado.otterscan.bbjubjub.fr",
	mainAddress: deployments[10200]?.ERC8270,
	depositsAddress: deployments[10200]?.DepositsGno,
	depositsContractAddress: "0xb97036A26259B7147018913bD58a774cf91acf25",
	gnoTokenAddress: "0x19C653Da7c37c66208fbfbE8908A5051B57b4C70",
    },
    gnosis: {
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
    },
    hoodi: {
	id: "hoodi",
	chainId: 560048,
	name: "Hoodi",
	currency: "ETH",
	rpcUrl: "https://hoodi.rpc.bbjubjub.fr",
	beaconApiUrl: "https://hoodi.beaconrpc.bbjubjub.fr",
	explorerUrl: "https://hoodi.otterscan.bbjubjub.fr",
	mainAddress: deployments[560048]?.ERC8270,
	depositsAddress: deployments[560048]?.DepositsGno,
    },
};

export function getNetwork(networkParam) {
    if (!networkParam) return null;
    return NETWORKS[networkParam.toLowerCase()] || 
	Object.values(NETWORKS).find(n => n.chainId.toString() === networkParam);
}
