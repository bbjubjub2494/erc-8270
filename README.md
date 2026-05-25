# source code for ERC-8270: Canonical Validator Wrapper

**UNDER DEVELOPMENT**

confer *TBD link to the ERC*

In addition to what is advertised in the ERC, we showcase support for Gnosis Chain without altering the ERC contract.

## Important Files

- `contracts/src/core/ERC8270.vy` main contract
- `contracts/src/core/WithdrawalReceiver.vy` deployed at the withdrawal address
- `contracts/src/periphery` utility contracts, NOT part of the ERC
- `contracts/scripts/Deploy.s.sol` deployment script
- `frontend/` vibe-coded web frontend for the ERC contracts

## Legal

In compliance with EIP-1, all art and smart contract code is released under CC0-1.0.
The GnosisToken test file retains the [GNU AGPL 3.0 license](./LICENSE.AGPL3) from Solmate.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
