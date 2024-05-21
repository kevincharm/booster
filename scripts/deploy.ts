import { ethers, run } from 'hardhat'
import { Booster__factory } from '../typechain-types'

const ANYRAND = '0x26881E8C452928A889654e4a8BaFBf205dD87812'
const TOKEN_ADDRESS = '0xa2eaf53712509dde1dc8f18af7c6576e69946be9'

async function main() {
    const [deployer] = await ethers.getSigners()
    const args: Parameters<Booster__factory['deploy']> = [
        ANYRAND,
        TOKEN_ADDRESS,
        [
            4, // common
            1, // rare
        ],
    ]
    const booster = await new Booster__factory(deployer)
        .deploy(...args)
        .then((tx) => tx.waitForDeployment())
    console.log(`Deployed Booster at: ${await booster.getAddress()}`)

    await new Promise((resolve) => setTimeout(resolve, 10_000))
    await run('verify:verify', {
        address: await booster.getAddress(),
        constructorArguments: args,
    })
}

main()
    .then(() => {
        console.log('Done')
        process.exit(0)
    })
    .catch((err) => {
        console.error(err)
        process.exit(1)
    })
