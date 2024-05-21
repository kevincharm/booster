import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { ethers } from 'hardhat'
import { time } from '@nomicfoundation/hardhat-network-helpers'
import {
    AddressLike,
    BigNumberish,
    ContractTransactionResponse,
    ZeroAddress,
    formatEther,
    hexlify,
    randomBytes,
} from 'ethers'
import { expect } from 'chai'
import {
    MockERC1155,
    MockBooster,
    MockBooster__factory,
    MockERC1155__factory,
    Booster,
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
        const commonTokenIds = Array(20)
            .fill(0)
            .map((_, i) => i + 1) // tokenId 1-20
        const rareTokenIds = Array(5)
            .fill(0)
            .map((_, i) => 21 + i) // tokenId 21-25
        await booster.loadCommons(
            commonTokenIds,
            commonTokenIds.map((_) => 2), // 2 each tokenId
        )
        await booster.loadRares(
            rareTokenIds,
            rareTokenIds.map((_) => 2), // 2 each tokenId
        )
        const allTokenIds = [
            ...commonTokenIds.map((tokenId) => [tokenId, tokenId]).flat(),
            ...rareTokenIds.map((tokenId) => [tokenId, tokenId]).flat(),
        ]
        const totalTokens = await booster.totalTokens()
        const tokensPerPack = await booster.tokensPerPack()
        const packs = Number(totalTokens / tokensPerPack)
        const openedTokenIds: bigint[] = []
        for (let i = 0; i < packs; ++i) {
            const { result } = await testOpen(
                booster,
                BigInt(hexlify(randomBytes(32))),
                bob.address,
            )
            openedTokenIds.push(...result)
        }
        openedTokenIds.sort((a, b) => {
            if (a < b) {
                return -1
            } else if (a > b) {
                return 1
            } else {
                return 0
            }
        })
        expect(openedTokenIds).to.deep.eq(allTokenIds)

        // let total = 0n
        // for (let i = 1; i <= 25; ++i) {
        //     total += await token.balanceOf(bob.address, i)
        // }
        // expect(total).to.eq(5n)
    })
})

async function testOpen(
    booster: MockBooster,
    seed: BigNumberish,
    receiver: AddressLike,
): Promise<{ tx: ContractTransactionResponse; result: bigint[] }> {
    const result = await booster.testOpen.staticCall(seed, receiver)
    const tx = await booster.testOpen(seed, receiver)
    return {
        tx,
        result,
    }
}
