/**
 * @type import('hardhat/config').HardhatUserConfig
 */

import {HardhatUserConfig} from 'hardhat/config'
import "@typechain/hardhat"
import "@nomiclabs/hardhat-waffle"


const config: HardhatUserConfig = {
  solidity: "0.8.0"
}

export default config;