# Consortium-KYC-Registry
Decentralized Consortium KYC/AML Utility Network Smart Contract Demo (FIN4020)
# Consortium-KYC-Registry (基于联盟链的数字身份与自动化合规网络)

## 1. 项目架构简介 (Project Architecture)

本项目针对传统金融机构在客户尽职调查（KYC）与反洗钱（AML）审查中的重复劳动、高昂成本及中心化隐私泄露痛点，设计并实现了一套**“链下数据存储 + 链上状态锚定”**的去中心化身份（DID）验证智能合约原型（`ConsortiumKYCRegistry.sol`）。

### 核心设计机制
* **零明文上链（GDPR 数据最小化原则）**：用户的个人身份信息（PII）经高熵随机盐（Salt）与 SHA-256 哈希处理后，在用户本地硬件环境（如 Secure Enclave）构建 Merkle Tree。区块链仅锚定顶层的 **Merkle Root**、签发机构地址、有效期限及撤销状态，彻底杜绝链上隐私泄露与高昂的存储 Gas 成本。
* **两段式直通处理（STP - Straight Through Processing）**：
  1. **链下公钥验真**：二级机构在本地调取一级持牌银行的公钥验证数字签名与 Merkle Proof，零 Gas 成本拦截伪造凭证。
  2. **链上状态裁决**：验签通过后，二级机构自动触发智能合约 `executeAutomatedOnboarding`，由合约自动核对发证机构权限（`ISSUER_ROLE`）、时间戳有效期及洗钱风险状态，实现毫秒级自动化开户放行。
* **全网实时风控同步**：一旦原发证银行检测到洗钱或欺诈行为，调用 `revokeKYC` 即可在全网同步冻结该凭证，消除机构间的信息孤岛时差。

---

## 2. 部署信息 (Sepolia Testnet Deployment)

* **部署网络 (Network)**：Ethereum Sepolia Testnet
* **智能合约地址 (Contract Address)**：`[請填入你的 Sepolia 合約地址，例如 0x71C...9A2]`
* **合约管理员地址 (Default Admin)**：`[請填入你的 Admin 錢包地址]`
* **Etherscan 浏览器查看与交互**：`https://sepolia.etherscan.io/address/[請填入你的 Sepolia 合約地址]`
* **编译器版本 (Compiler)**：`Solidity ^0.8.20` (依赖库：`@openzeppelin/contracts/access/AccessControl.sol`)

---

## 3. 端到端测试步骤说明 (Testing Workflow)

测试人员可通过 **Remix IDE** 或 **Sepolia Etherscan (`Write Contract` / `Read Contract` 页面)** 依序模拟以下四个角色的完整业务闭环：

### 角色准备
* **Admin**：部署合约的联盟网络管理员账号
* **Bank A**：一级持牌验证银行账号
* **User**：普通开户用户地址（测试用钱包地址）
* **Bank B**：二级金融机构（如券商、虚拟银行）账号

---

### 步骤一：联盟权限授予 (Admin $\rightarrow$ Bank A)
1. 切换至 **Admin** 账号，查询常量函数 `ISSUER_ROLE()` 获取角色哈希码：
   `0x114e74f6ea3bd819998f78687bf295b89f3bc4d3f0cf820d457d1c3f1a09c542`
2. 调用 `grantRole(role, account)`：
   * `role`: 填入上述 `ISSUER_ROLE` 哈希码
   * `account`: 填入 **Bank A** 的钱包地址
3. 提交交易，完成一级持牌机构准入授权。

### 步骤二：一级银行链上锚定 (Bank A 锚定 User 状态)
1. 切换至 **Bank A** 账号，调用 `anchorKYC(user, merkleRoot, validityDuration)`：
   * `user`: 填入 **User** 的钱包地址
   * `merkleRoot`: 填入模拟的 32 bytes 加盐根哈希，例如：
     `0x9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08`
   * `validityDuration`: 填入凭证有效秒数，例如 `31536000`（代表 1 年有效期）
2. 提交交易，区块链触发 `KYCAnchored` 事件，用户合规指纹成功上链。

### 步骤三：二级机构自动化验证与放行 (Bank B 核验)
1. 切换至 **Bank B** 账号（模拟用户已通过链下公钥验签）。
2. **纯状态查询（免费读取）**：调用 `checkVerificationStatus(user)`，传入 **User** 地址，系统直接返回 `true`。
3. **触发自动开户（链上执行）**：调用 `executeAutomatedOnboarding(user)`，传入 **User** 地址并提交交易。合约自动比对各项条件通过后，触发 `AutoCompliancePassed` 事件，完成无人工干预的自动开户放行。

### 步骤四：洗钱风控拦截与全网撤销 (异常测试)
1. 切换回原发证机构 **Bank A** 账号，调用 `revokeKYC(user, reason)`：
   * `user`: 填入 **User** 地址
   * `reason`: 输入撤销原因，例如 `"AML Risk Flag"`
2. 再次切换至 **Bank B** 账号尝试调用 `executeAutomatedOnboarding(user)`。
3. **预期结果**：交易被智能合约自动拦截并回滚（Revert），提示 `KYC Registry: Record is Expired, Revoked, or Invalid`，验证全网毫秒级风控阻断生效。
