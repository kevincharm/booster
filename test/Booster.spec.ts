import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { ethers } from 'hardhat'
import { time } from '@nomicfoundation/hardhat-network-helpers'
import { ZeroAddress, formatEther } from 'ethers'
import { expect } from 'chai'
import {
    MockERC1155,
    MockBooster,
    MockBooster__factory,
    MockERC1155__factory,
} from '../typechain-types'

const ANYRAND = '0x26881E8C452928A889654e4a8BaFBf205dD87812'
const TOKEN_ADDRESS = '0xad5c50fafe2b971d98f37a07c8a532381cce3a0b'

describe('Booster', () => {
    let deployer: SignerWithAddress
    let bob: SignerWithAddress
    let alice: SignerWithAddress
    let booster: MockBooster
    let token: MockERC1155
    beforeEach(async () => {
        ;[deployer, bob, alice] = await ethers.getSigners()
        token = await new MockERC1155__factory(deployer).deploy()
        booster = await new MockBooster__factory(deployer).deploy(
            ANYRAND,
            await token.getAddress(),
            [
                4, // common
                1, // rare
            ],
        )
    })

    it('works', async () => {
        await token.setApprovalForAll(await booster.getAddress(), true)
        await booster.loadCommons(
            [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
            [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
        )
        await booster.loadRares([21, 22, 23, 24, 25], [2, 2, 2, 2, 2])
        await booster.testOpen(69420, bob.address)

        let total = 0n
        for (let i = 1; i <= 25; ++i) {
            total += await token.balanceOf(bob.address, i)
        }
        expect(total).to.eq(5n)
    })
})
