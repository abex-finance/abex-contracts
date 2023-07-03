import { Connection, Ed25519Keypair, JsonRpcProvider, RawSigner, SUI_CLOCK_OBJECT_ID, TransactionBlock } from '@mysten/sui.js';
import { Buffer } from 'buffer';
import minimist from 'minimist';


interface IVault {
  reservingFeeModel: string;
  weight: string;
}

interface ISymbol {
  supportedCollaterals: string[];
  fundingFeeModel: string;
  positionConfig: string;
}

interface ICoin {
  module: string;
  metadata: string;
  treasury: string | null;
}

export interface IDeployments {
  abexCore: {
    package: string;
    upgradeCap: string;
    adminCap: string;
    market: string;
    alpMetadata: string;
    vaultsParent: string;
    symbolsParent: string;
    positionsParent: string;
    rebaseFeeModel: string;
    vaults: {
      [key: string]: IVault;
    };
    symbols: {
      [key: string]: ISymbol;
    };
  };
  abexFeeder: {
    package: string;
    upgradeCap: string;
    feeder: {
      [key: string]: string;
    };
  };
  coins: {
    [key: string]: ICoin;
  };
  coinDecimal: {
    [key: string]: number;
  };
}

function toCamelCase(str: string): string {
  return str.replace(/_([a-z])/g, (match, letter) => letter.toUpperCase());
}

function parse(obj: any): any {
  if (typeof obj !== 'object' || obj === null) {
    return obj;
  }

  if (Array.isArray(obj)) {
    return obj.map(parse);
  }

  const newObj: any = {};

  for (const key in obj) {
    const camelCaseKey = toCamelCase(key);
    newObj[camelCaseKey] = parse(obj[key]);
  }

  return newObj;
}

class Builder {
  provider: JsonRpcProvider;
  sender: RawSigner;
  txb: TransactionBlock;
  deploymentsFile: string;
  deployments: IDeployments;
  pythPackageAddress: string;
  pythStateAddress: string;
  wormPackageAddress: string;
  wormStateAddress: string;

  constructor(
    network: string,
    senderPrivateKey: string,
    deploymentsFile: string,
    pythPackageAddress: string,
    pythStateAddress: string,
    wormPackageAddress: string,
    wormStateAddress: string,
  ) {
    const keypair = Ed25519Keypair.fromSecretKey(this.#base64ToUint8Array(senderPrivateKey))

    this.provider = this.#getProvider(network);
    this.sender = new RawSigner(keypair, this.provider);
    this.txb = new TransactionBlock();
    this.deploymentsFile = deploymentsFile;
    this.deployments = parse(require(this.deploymentsFile))
    this.pythPackageAddress = pythPackageAddress;
    this.pythStateAddress = pythStateAddress;
    this.wormPackageAddress = wormPackageAddress;
    this.wormStateAddress = wormStateAddress;
  }

  #getProvider(network: string = 'testnet') {
    // Construct your connection:
    let connection;
    switch (network) {
      case 'devnet':
        connection = new Connection({
          fullnode: 'https://explorer-rpc.devnet.sui.io/',
          faucet: 'https://explorer-rpc.devnet.sui.io/gas',
        });
        break;
      case 'testnet':
        connection = new Connection({
          fullnode: 'https://explorer-rpc.testnet.sui.io/',
          faucet: 'https://explorer-rpc.testnet.sui.io/gas',
        });
        break;
      case 'mainnet':
        connection = new Connection({
          fullnode: 'https://explorer-rpc.mainnet.sui.io/',
          faucet: 'https://explorer-rpc.mainnet.sui.io/gas',
        });
        break;
      default:
        connection = new Connection({
          fullnode: 'https://explorer-rpc.devnet.sui.io/',
          faucet: 'https://explorer-rpc.devnet.sui.io/gas',
        });
    }
    // connect to a custom RPC server
    return new JsonRpcProvider(connection);
  }

  #base64ToUint8Array(base64: string): Uint8Array {
    // Create a Buffer from the Base64 encoded string
    const buffer = Buffer.from(base64, 'base64');

    // Convert the Buffer to a Uint8Array
    const uint8Array = new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.byteLength);

    return uint8Array;
  }

  async addPythFeeds() {
    // TODO: Fetch correct vaa bytes from pyth
    const vaa_bytes =
      "AQAAAAABAMN885gNTVEako6fczJq22AOFSRWdUsUOxPQVHSnxhj3ecU2gJVDBlAcY6G9FWmGCcGcdZ/5iVXQCm+0loHvfqwAZE/kXQAAAAAAGqJ4OdZBsHdDwMtfaMUfjNMdLAdivsANxvzSVDPvGrW2AAAAAADugxEBUDJXSAADAAEAAQIABQCdWnl7akEQMaEEfYaw/fhuJFW+jn/vFq7yPbIJcj2vlB9hIm05vuoZ0zTxfC/rzifhJkbYRnWSTrsCuc2upocn4wAAAABBxD4gAAAAAAAJ2WD////4AAAAAEIrzm4AAAAAAAn/ewEAAAABAAAAAgAAAABkT+RdAAAAAGRP5F0AAAAAZE/kXAAAAABBxC0/AAAAAAAJi/EAAAAAZE/kXLWIXWbTUV6YNI7DMlk7XRbg/bhT77Ye1dzAvPgOkWCB11ZqO6f3KG7VT0rn6YP0QgrgseDziS4R+cSrEHu617kAAAAAZCplIAAAAAAAEu4I////+AAAAABkvzOKAAAAAAAQZDgBAAAAAQAAAAIAAAAAZE/kXQAAAABkT+RdAAAAAGRP5FwAAAAAZCplIAAAAAAAFIotAAAAAGRP5Fw3+21L/xkSgKfP+Av17aeofBUakdmoW6So+OLPlX5BjbMn2c8OzXk6F1+nCsjS3BCdRGJ1jlVpYsSoewLsTz8VAAAAAC1gXb0AAAAAAAdkLv////gAAAAALZa00gAAAAAABpwgAQAAAAEAAAACAAAAAGRP5F0AAAAAZE/kXQAAAABkT+RcAAAAAC1gXb0AAAAAAAdkLgAAAABkT+RcHNsaXh40VtKXfuDT1wdlI58IpChVuVCP1HnhXG3E0f7s9VN3DZsQll+Ptkdx6T9WkKGC7cMr5KMjbgyqpuBYGgAAAAewLri2AAAAAAEnq0n////4AAAAB7uEHmgAAAAAAV8hnAEAAAABAAAAAgAAAABkT+RdAAAAAGRP5F0AAAAAZE/kXAAAAAewBz2PAAAAAAE4kisAAAAAZE/kXGogZxwOP4yyGc4/RuWuCWpPL9+TbSvU2okl9wCH1R3YMAKUeVmHlykONjihcSwpveI2fQ7KeU93iyW1pHLxkt4AAAACtJQuKQAAAAAAn4lX////+AAAAAK3aIHUAAAAAACmrg4BAAAAAQAAAAIAAAAAZE/kXQAAAABkT+RdAAAAAGRP5FwAAAACtJOhZQAAAAAAnAlPAAAAAGRP5Fw=";

    let [verified_vaa] = this.txb.moveCall({
      target: `${this.wormPackageAddress}::vaa::parse_and_verify`,
      arguments: [
        this.txb.object(this.wormStateAddress),
        this.txb.pure([...Buffer.from(vaa_bytes, "base64")]),
        this.txb.object(SUI_CLOCK_OBJECT_ID),
      ],
    });

    this.txb.moveCall({
      target: `${this.pythPackageAddress}::pyth::create_price_feeds`,
      arguments: [
        this.txb.object(this.pythStateAddress),
        this.txb.makeMoveVec({
          type: `${this.wormPackageAddress}::vaa::VAA`,
          objects: [verified_vaa],
        }), // has type vector<VAA>,
        this.txb.object(SUI_CLOCK_OBJECT_ID),
      ],
    });

  }

  async call() {
    const result = await this.sender.signAndExecuteTransactionBlock({
      transactionBlock: this.txb,
      options: {
        showInput: true,
        showEffects: true,
        showEvents: true,
        showObjectChanges: true,
        showBalanceChanges: true,
      }
    })
  }

  async #postProcess() {
    // TODO: Add result json to deployments.json
  }
}

const args = minimist(process.argv.slice(2));
const network = args.network || 'testnet';
const senderPrivateKey = args.senderPrivateKey || '';
const deploymentsFile = args.deploymentsFile || './deployments.json';
const pythPackageAddress = args.pythPackageAddress || '';
const pythStateAddress = args.pythStateAddress || '';
const wormPackageAddress = args.wormPackageAddress || '';
const wormStateAddress = args.wormStateAddress || '';

const builder = new Builder(network, senderPrivateKey, deploymentsFile, pythPackageAddress, pythStateAddress, wormPackageAddress, wormStateAddress);
builder.addPythFeeds();
builder.call().then(console.log);