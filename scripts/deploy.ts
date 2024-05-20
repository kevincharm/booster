import { ethers, run } from 'hardhat'
import { Booster__factory } from '../typechain-types'

const ANYRAND = '0x26881E8C452928A889654e4a8BaFBf205dD87812'
const TOKEN_ADDRESS = '0xad5c50fafe2b971d98f37a07c8a532381cce3a0b'

async function main() {
    const [deployer] = await ethers.getSigners()
    const args: Parameters<Booster__factory['deploy']> = [
        ANYRAND,
        TOKEN_ADDRESS,
        [
            {
                rarity: 0,
                amount: 4,
            },
            {
                rarity: 1,
                amount: 1,
            },
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
