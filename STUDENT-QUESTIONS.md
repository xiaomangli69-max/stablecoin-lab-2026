# STUDENT-QUESTIONS.md — Discussion questions (submit with your repo)

Answer directly under each question. 150–300 words each — **reasoning over length**.

---

## A. Permission design

**A1.** The vault holds `MINTER_ROLE`, so it can `burn` any user's balance. Explain why that is a risk, then write out how you would change `Vault` and `SimpleStablecoin` to remove it.

> Your answer:
>
> Risk: In the current SimpleStablecoin code, the permission check for the burn function is onlyRole(MINTER_ROLE). To enable the Vault to destroy users' coins during redemption, we directly assigned the MINTER_ROLE to the Vault. However, this means that the Vault becomes a super administrator. As long as there are vulnerabilities in the Vault contract or insiders engage in malicious behavior, it can bypass user authorization (approve) and instantly zero out any account's sUSD balance. This is a fatal centralized backdoor that will completely destroy user trust.
>
> How to change: In SimpleStablecoin: add a dedicated BURNER_ROLE instead of reusing MINTER_ROLE to execute burns. At the same time, it is mandated that only redemptions initiated by the user themselves can destroy their corresponding balances.
>
> In the Vault: Change the role of the Vault from MINTER_ROLE to BURNER_ROLE. AndWhen calling burn, only the balance of msg.sender (the current user who initiated the redemption) can be burned, and user authorization is required. For example, restrict it to stable.burn(msg.sender, amount), and never pass in the address of other users.

<br><br><br>

**A2.** In this contract `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` all go to the same address. How would you split them in production, and who holds each?

> Your answer:
>
> In the current code, it is extremely dangerous to have DEFAULT_ADMIN_ROLE, MINTER_ROLE, and PAUSER_ROLE all pointing to the same address, as this constitutes a "Single Point of Failure". Permissions must be split.
>
> DEFAULT_ADMIN_ROLE: It should not be assigned to an EOA address (personal wallet). Instead, it should be assigned to a "Multisig Wallet". Alternatively, it can be assigned to a "DAO", where all token holders are treated as shareholders, and any major decisions are made through voting by everyone. In terms of code implementation, DEFAULT_ADMIN_ROLE should only have the power to assign roles through grantRole and revokeRole, and must not be granted business permissions such as mint and pause at the same time.
>
> MINTER_ROLE: Grant the Vault contract the MINTER_ROLE, but as stated in A1, it must not be allowed to possess unrestricted burn rights simultaneously. Therefore, allow the Vault to possess the MINTER_ROLE to perform deposit minting, but an independent BURNER_ROLE must be introduced in SimpleStablecoin. The Vault can only destroy balances actively redeemed by users through the BURNER_ROLE.
>
> PAUSER_ROLE: This role should not be granted directly to an individual wallet, but rather to a Multisig Wallet contract. Since hacker attacks can occur very quickly, DAO voting may not be able to respond in time, so the Security Council needs to be able to complete the Multisig and execute pause() within a few minutes. To prevent abuse, the contract logic can be set up such that resuming operation after a pause requires DAO voting, or the paused state automatically expires after 7 days.

<br><br><br>

---

## B. Pausing and redemption

**B1.** `_update` is the single entry point for every balance change, so `pause()` freezes transfers, minting and redemption together. If you wanted "pause transfers but **allow redemption**", how would you change it? Give the approach — full code not required.

> Your answer:
>
> "_update" is the essential underlying path for all transfers, minting, and burning operations. The current code directly adds a pause on "_update", resulting in users being completely locked out.
>
> To achieve "pausing regular transfers but allowing redemptions", the modification approach is: instead of implementing a one-size-fits-all solution at the outermost level, we should add a judgment within the _update function.
>
> When the contract is in a paused state, check the transfer parties (from and to) of this transaction. If it is a mutual transfer between ordinary users, directly report an error and reject it; but if one party of this transaction is the Vault, it indicates that the user is performing a redemption operation, and it is allowed to proceed.
>
> This is equivalent to only keeping the escape route of "user - vault" open during the suspension period, while blocking the panic selling in the market of "user - user".In specific implementation, a whitelist can be set for the vault address.

<br><br><br>

**B2.** In 2008, when a money-market fund "broke the buck", redemptions were frozen for days. In 2023 USDC depegged to $0.87 after a reserve bank failed, but redemptions were **not** shut. Compare the two responses — what does closing the redemption channel, or leaving it open, do to a stablecoin?

> Your answer:
>
> The comparison between these two historical events :
>
> The consequences of freezing redemptions in 2008: When money funds closed their redemption channels, investors fell into extreme panic. The inability to withdraw money led to an instantaneous collapse of market confidence, and everyone sold at any cost, making the "liquidity crisis" immediately escalate into a "solvency crisis". Closing the redemption channel was equivalent to declaring the system dead, and ultimately, the fund could not escape the fate of collapse.
>
> The consequence of USDC remaining open in 2023: Despite a reserve bank failed, which caused USDC to temporarily de-peg to $0.87, Circle resolutely kept the redemption channel open. This sent a strong signal to the market that "the underlying dollar reserves are still there." Arbitrageurs saw the huge profits from buying at $0.87 and redeeming at $1.00, and they entered the market to buy USDC and redeem it. This spontaneous market arbitrage behavior created huge buying pressure, which quickly pushed the price of USDC back to $1.00 within just a few days.
>
> Conclusion: The redemption channel is the lifeline of stable coins. Closing it will trigger a trust collapse and a death spiral; keeping it open can activate the arbitrage mechanism in the market, relying on market forces to self-repair the detachment.

<br><br><br>

---

## C. Depeg analysis

**C1.** Under what conditions does this coin depeg? Distinguish at least two classes of cause, and say how each one shows up in the invariant `totalCollateral() >= totalSupply()`.

> Your answer:
> 
> There are typically two fundamental reasons for stablecoin de-pegging, which exhibit distinct behaviors in terms of invariants:
> 
> Reason 1: Solvency Issue
> The real money in the vault is stolen, misappropriated, or the collateral (if it is Ethereum, etc.) experiences a sharp price drop.
> Invariant violation: The invariant is broken (totalCollateral < totalSupply). As the system suddenly has coins without asset backing, people notice the empty vault and will frantically sell, leading to a price crash.
> 
> Reason 2: Liquidity Issue
> The funds in the vault are fully sufficient (the invariant still holds), but the project party has pressed the pause button, or legal/regulatory requirements have frozen the redemption channel. Everyone has coins in hand, but they cannot exchange them back into US dollars.
> Invariant manifestation: The invariant still holds (totalCollateral >= totalSupply is not violated). Mathematically, it is sound, but in reality, due to the inability to redeem, everyone panics and sells, causing the price to still de-anchor (for example, falling to $0.9).



<br><br><br>

**C2.** Suppose an attacker bribes their way to `MINTER_ROLE`, mints 1,000,000 sUSD out of nothing and redeems it all. Describe the flow of funds, and name the step that could have stopped them.

> Your answer:
> 
> Capital flow:
> 1. The attacker obtains the `MINTER_ROLE` permission through bribery.
> 2. The attacker calls the `mint` function, minting 1,000,000 sUSD for themselves out of thin air, causing an increase in `totalSupply`.
> 3. The attacker uses these sUSD to call the `redeem` function of the vault for redemption.
> 4. The vault destroyed these 1,000,000 sUSD and transferred the real collateral (USDC) inside the vault to the attacker. Ultimately, the attacker absconded with the funds, draining the vault and leaving other users' stablecoins unsupported.
>
> Steps that can be prevented:
> The root cause of this attack lies in centralized permission management. The steps that can be taken to prevent it include:
> 1. Use a multisig wallet to manage the `MINTER_ROLE`, thus preventing a single individual from gaining access through bribery.
> 2. Add a time lock to the coin minting permission, delaying the execution of large-value coin minting by 48 hours to allow the community time to respond and intercept.
> 3. Set a daily minting rate limit to prevent the sudden printing of a large amount of funds out of thin air and emptying the vault.

<br><br><br>

---

## D. Toward RWA

**D1.** Right now the collateral is `MockUSDC` and `totalCollateral()` just reads an on-chain balance — simple and reliable. If the collateral were **US Treasuries**, could this invariant still be written that way? What new problems appear?

> Your answer:
> 
> If the collateral is a US Treasury bond, `totalCollateral()` will cannot be implemented directly by reading the on-chain balance as it is currently done. Treasury bonds are off-chain assets, and an Oracle must be introduced to transmit the off-chain valuation to the on-chain system.
>
> The following new issues will arise:
> 1. Oracle risk: Contracts rely on off-chain price feeds. If the oracle is manipulated or there is data latency, it can lead to incorrect valuation of collateral, triggering erroneous liquidation or system insolvency.
> 2. Price fluctuation: The price of treasury bonds fluctuates due to interest rate changes, leading to a non-constant mortgage rate, necessitating the introduction of more complex risk management mechanisms.
> 3. Clearing and Liquidity Risk: Treasury bonds cannot be instantly liquidated like cryptocurrency assets. Off-chain legal processes and settlement times (such as T+1) can lead to clearing delays, potentially resulting in bad debts during severe market fluctuations.
> 4. Trust and Custody Risk: It is necessary to trust the custodian institutions under the chain to hold treasury bonds, which reintroduces the issue of centralized trust.

<br><br><br>

**D2.** If the collateral were **a building**, how would you put it inside this vault? Which off-chain roles or legal structures would you have to introduce?

> Your answer:
> 
> To incorporate a building into this digital vault, we must achieve this through asset tokenization:
>
> 1. Legal structure (off-chain): A special purpose vehicle (SPV) or trust must be established, with the SPV legally holding the property rights of the real estate project in the real world. This isolates the property from the bankruptcy of the project party.
> 2. Token issuance (on-chain): SPV divides the ownership of the property and issues on-chain tokens (such as ERC-20 or ERC-721) representing the asset shares. The vault is collateralized by these tokens representing the property rights.
> 3. Introduction of off-chain roles:
> Custodian: Responsible for the daily management of physical real estate, including rent collection and tax payment.
> Appraiser: Regularly conduct valuation of real estate projects and feed the prices to the on-chain contract through an oracle.
> Legal compliance consultant: Ensure that in the event of default liquidation, on-chain token holders possess legitimate recourse and property transfer rights.
> Ultimately, `totalCollateral()` will read the product of the token balance representing the property rights and its oracle valuation.

<br><br><br>

---

## E. Tests (Tier 1 required — this is Ex4)

Turn the red tests green in `test/exercises/01_LoopTasks.t.sol` to cover the scenarios below, and write your test function names here:

| Scenario | Your test function name |
|---|---|
| Minting by a non-minter reverts | |
| Transfers revert while paused | |
| **Redemption** reverts while paused | |
| An attacker cannot burn someone else's balance | |
| ...but the vault holding `MINTER_ROLE` can | |

That last pair is meant to be read together: the guard is written correctly, but the key was handed to the vault. Keep it in mind when you answer A1.

Now write one more scenario you consider **most likely to be attacked**, and say why you picked it:

> Your answer:
