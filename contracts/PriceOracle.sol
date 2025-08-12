// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/**
 * @title PriceOracle
 * @dev Pyth Network-based price oracle for Bitcoin and other assets on Core DAO
 */
contract PriceOracle is Ownable, Pausable {
    struct PriceFeed {
        bytes32 priceId;          // Pyth price feed ID
        uint256 maxStaleness;     // Maximum acceptable staleness in seconds
        uint8 targetDecimals;     // Target decimals for price normalization
        bool isActive;            // Whether the feed is active
        uint256 minPrice;         // Minimum valid price (in target decimals)
        uint256 maxPrice;         // Maximum valid price (in target decimals)
        string description;       // Human readable description
    }

    struct PriceData {
        uint256 price;            // Price in target decimals
        uint256 timestamp;        // Price timestamp
        uint256 confidence;       // Price confidence interval
        bool isStale;            // Whether price is stale
    }

    // Constants
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant MAX_STALENESS = 3600; // 1 hour default
    uint256 public constant MAX_CONFIDENCE_DEVIATION = 1000; // 10% max confidence deviation
    uint256 public constant BASIS_POINTS = 10000; // 10000 basis points = 100%
    
    // Pyth contract
    IPyth public immutable pyth;
    
    // State variables
    mapping(string => PriceFeed) public priceFeeds;
    mapping(string => PriceData) public latestPrices;
    string[] public supportedAssets;
    
    // Circuit breaker
    bool public circuitBreakerTripped;
    uint256 public circuitBreakerThreshold = 2000; // 20% price change threshold
    
    // Events
    event PriceFeedAdded(string asset, bytes32 priceId);
    event PriceFeedUpdated(string asset, bytes32 priceId);
    event PriceFeedRemoved(string asset);
    event PriceUpdated(string asset, uint256 price, uint256 timestamp, uint256 confidence);
    event CircuitBreakerTripped(string asset, uint256 price, uint256 previousPrice);
    event CircuitBreakerReset();

    constructor(address _pyth, address _owner) Ownable(_owner) {
        pyth = IPyth(_pyth);
        _initializePriceFeeds();
    }

    function _initializePriceFeeds() private {
        // Initialize with Core DAO compatible Pyth price feeds
        // These are the actual Pyth price feed IDs for major assets
        
        // BTC/USD feed
        _addPriceFeed(
            "BTC",
            0xf9c0172ba10dfa4d19088d94f5bf61d3b54d5bd7483a322a982e1373ee8ea31b, // Pyth BTC/USD price ID
            MAX_STALENESS,
            8,    // 8 decimals for BTC price
            30000e8, // $30,000 min price
            200000e8, // $200,000 max price
            "Bitcoin/USD"
        );
        
        // ETH/USD feed
        _addPriceFeed(
            "ETH",
            0xca80ba6dc32e08d06f1aa886011eed1d77c77be9eb761cc10d72b7d0a2fd57a6, // Pyth ETH/USD price ID
            MAX_STALENESS,
            8,    // 8 decimals for ETH price
            1000e8,  // $1,000 min price
            10000e8, // $10,000 max price
            "Ethereum/USD"
        );
        
        // USDT/USD feed
        _addPriceFeed(
            "USDT",
            0x1fc18861232290221461220bd4e2acd1dcdfbc89c84092c93c18bdc7756c1588, // Pyth USDT/USD price ID
            MAX_STALENESS,
            8,    // 8 decimals for USDT price
            0.95e8,  // $0.95 min price
            1.05e8,  // $1.05 max price
            "Tether/USD"
        );
        
        // USDC/USD feed
        _addPriceFeed(
            "USDC",
            0x41f3625971ca2ed2263e78573fe5ce23e13d2558ed3f2e47ab0f84fb9e7ae722, // Pyth USDC/USD price ID
            MAX_STALENESS,
            8,    // 8 decimals for USDC price
            0.95e8,  // $0.95 min price  
            1.05e8,  // $1.05 max price
            "USD Coin/USD"
        );

        // CORE/USD feed (if available on Pyth)
        _addPriceFeed(
            "CORE",
            0x033115217b52a823cfd3c40fa8e645707fa94da672a03f1636f644417a233466, // Placeholder - may need custom oracle
            MAX_STALENESS,
            8,    // 8 decimals for CORE price
            0.1e8,   // $0.10 min price
            100e8,   // $100 max price
            "Core DAO/USD"
        );
    }

    /**
     * @dev Add a new price feed
     */
    function addPriceFeed(
        string memory asset,
        bytes32 priceId,
        uint256 maxStaleness,
        uint8 targetDecimals,
        uint256 minPrice,
        uint256 maxPrice,
        string memory description
    ) external onlyOwner {
        _addPriceFeed(asset, priceId, maxStaleness, targetDecimals, minPrice, maxPrice, description);
    }

    function _addPriceFeed(
        string memory asset,
        bytes32 priceId,
        uint256 maxStaleness,
        uint8 targetDecimals,
        uint256 minPrice,
        uint256 maxPrice,
        string memory description
    ) internal {
        require(priceId != bytes32(0), "Invalid price ID");
        require(maxStaleness > 0, "Invalid staleness threshold");
        require(minPrice < maxPrice, "Invalid price range");
        
        // Check if asset is new
        bool isNewAsset = !priceFeeds[asset].isActive;
        
        priceFeeds[asset] = PriceFeed({
            priceId: priceId,
            maxStaleness: maxStaleness,
            targetDecimals: targetDecimals,
            isActive: true,
            minPrice: minPrice,
            maxPrice: maxPrice,
            description: description
        });
        
        if (isNewAsset) {
            supportedAssets.push(asset);
        }
        
        emit PriceFeedAdded(asset, priceId);
    }

    /**
     * @dev Update an existing price feed
     */
    function updatePriceFeed(
        string memory asset,
        bytes32 priceId,
        uint256 maxStaleness,
        uint8 targetDecimals,
        uint256 minPrice,
        uint256 maxPrice,
        string memory description
    ) external onlyOwner {
        require(priceFeeds[asset].isActive, "Price feed not found");
        
        _addPriceFeed(asset, priceId, maxStaleness, targetDecimals, minPrice, maxPrice, description);
        
        emit PriceFeedUpdated(asset, priceId);
    }

    /**
     * @dev Remove a price feed
     */
    function removePriceFeed(string memory asset) external onlyOwner {
        require(priceFeeds[asset].isActive, "Price feed not found");
        
        priceFeeds[asset].isActive = false;
        
        // Remove from supported assets array
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            if (keccak256(bytes(supportedAssets[i])) == keccak256(bytes(asset))) {
                supportedAssets[i] = supportedAssets[supportedAssets.length - 1];
                supportedAssets.pop();
                break;
            }
        }
        
        emit PriceFeedRemoved(asset);
    }

    /**
     * @dev Get the latest price for an asset
     */
    function getPrice(string memory asset) external view whenNotPaused returns (uint256) {
        require(priceFeeds[asset].isActive, "Price feed not supported");
        require(!circuitBreakerTripped, "Circuit breaker tripped");
        
        PriceFeed memory feed = priceFeeds[asset];
        
        // Get price from Pyth
        PythStructs.Price memory pythPrice = pyth.getPriceUnsafe(feed.priceId);
        
        require(pythPrice.price > 0, "Invalid price");
        require(pythPrice.publishTime > 0, "Invalid timestamp");
        
        // Check staleness
        require(
            block.timestamp - pythPrice.publishTime <= feed.maxStaleness,
            "Price too stale"
        );
        
        // Convert price to target decimals
        uint256 scaledPrice = _scalePythPrice(pythPrice, feed.targetDecimals);
        
        // Validate price is within acceptable range
        require(
            scaledPrice >= feed.minPrice && scaledPrice <= feed.maxPrice,
            "Price outside valid range"
        );
        
        // Check confidence interval
        uint256 confidence = _scalePythPrice(
            PythStructs.Price({
                price: int64(uint64(pythPrice.conf)),
                conf: 0,
                expo: pythPrice.expo,
                publishTime: pythPrice.publishTime
            }),
            feed.targetDecimals
        );
        
        // Ensure confidence is reasonable (not more than 10% of price)
        require(
            confidence * BASIS_POINTS <= scaledPrice * MAX_CONFIDENCE_DEVIATION,
            "Price confidence too low"
        );
        
        return _scaleToStandardPrecision(scaledPrice, feed.targetDecimals);
    }

    /**
     * @dev Get price with additional metadata
     */
    function getPriceData(string memory asset) external view whenNotPaused returns (
        uint256 price,
        uint256 timestamp,
        uint256 confidence,
        bool isStale
    ) {
        require(priceFeeds[asset].isActive, "Price feed not supported");
        
        PriceFeed memory feed = priceFeeds[asset];
        PythStructs.Price memory pythPrice = pyth.getPriceUnsafe(feed.priceId);
        
        require(pythPrice.price > 0, "Invalid price");
        require(pythPrice.publishTime > 0, "Invalid timestamp");
        
        uint256 scaledPrice = _scalePythPrice(pythPrice, feed.targetDecimals);
        uint256 scaledConfidence = _scalePythPrice(
            PythStructs.Price({
                price: int64(uint64(pythPrice.conf)),
                conf: 0,
                expo: pythPrice.expo,
                publishTime: pythPrice.publishTime
            }),
            feed.targetDecimals
        );
        
        bool priceIsStale = block.timestamp - pythPrice.publishTime > feed.maxStaleness;
        
        return (
            _scaleToStandardPrecision(scaledPrice, feed.targetDecimals),
            pythPrice.publishTime,
            _scaleToStandardPrecision(scaledConfidence, feed.targetDecimals),
            priceIsStale
        );
    }

    /**
     * @dev Update prices with fee payment to Pyth
     */
    function updatePrices(bytes[] calldata priceUpdateData) external payable {
        // Get the required fee for updating prices
        uint256 fee = pyth.getUpdateFee(priceUpdateData);
        require(msg.value >= fee, "Insufficient fee");
        
        // Update prices on Pyth contract
        pyth.updatePriceFeeds{value: fee}(priceUpdateData);
        
        // Update our internal price cache and check circuit breaker
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            string memory asset = supportedAssets[i];
            _updatePrice(asset);
        }
        
        // Refund excess fee
        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value - fee);
        }
    }

    function _updatePrice(string memory asset) internal {
        if (!priceFeeds[asset].isActive) return;
        
        PriceFeed memory feed = priceFeeds[asset];
        
        try pyth.getPriceUnsafe(feed.priceId) returns (PythStructs.Price memory pythPrice) {
            if (pythPrice.price <= 0 || pythPrice.publishTime == 0) return;
            
            uint256 scaledPrice = _scalePythPrice(pythPrice, feed.targetDecimals);
            uint256 standardPrice = _scaleToStandardPrecision(scaledPrice, feed.targetDecimals);
            
            // Check for circuit breaker condition
            if (latestPrices[asset].price > 0) {
                uint256 previousPrice = latestPrices[asset].price;
                uint256 priceChange = standardPrice > previousPrice 
                    ? ((standardPrice - previousPrice) * 10000) / previousPrice
                    : ((previousPrice - standardPrice) * 10000) / previousPrice;
                
                if (priceChange > circuitBreakerThreshold) {
                    circuitBreakerTripped = true;
                    emit CircuitBreakerTripped(asset, standardPrice, previousPrice);
                    return;
                }
            }
            
            // Calculate confidence
            uint256 confidence = _scalePythPrice(
                PythStructs.Price({
                    price: int64(uint64(pythPrice.conf)),
                    conf: 0,
                    expo: pythPrice.expo,
                    publishTime: pythPrice.publishTime
                }),
                feed.targetDecimals
            );
            
            // Update stored price
            latestPrices[asset] = PriceData({
                price: standardPrice,
                timestamp: pythPrice.publishTime,
                confidence: _scaleToStandardPrecision(confidence, feed.targetDecimals),
                isStale: block.timestamp - pythPrice.publishTime > feed.maxStaleness
            });
            
            emit PriceUpdated(asset, standardPrice, pythPrice.publishTime, confidence);
        } catch {
            // Silently fail for individual price updates
        }
    }

    /**
     * @dev Scale Pyth price to target decimals
     */
    function _scalePythPrice(
        PythStructs.Price memory pythPrice,
        uint8 targetDecimals
    ) internal pure returns (uint256) {
        require(pythPrice.price >= 0, "Negative price");
        
        uint256 price = uint256(uint64(pythPrice.price));
        int32 expo = pythPrice.expo;
        
        if (expo >= 0) {
            // Positive exponent: multiply by 10^expo
            price = price * (10 ** uint32(expo));
        } else {
            // Negative exponent: divide by 10^(-expo)
            uint256 divisor = 10 ** uint32(-expo);
            price = price / divisor;
        }
        
        // Scale to target decimals (Pyth typically uses different decimals than our target)
        // This assumes Pyth price is in USD with varying decimals based on expo
        return price;
    }

    /**
     * @dev Scale price to standard 18 decimal precision
     */
    function _scaleToStandardPrecision(uint256 price, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) {
            return price;
        } else if (decimals < 18) {
            return price * (10 ** (18 - decimals));
        } else {
            return price / (10 ** (decimals - 18));
        }
    }

    /**
     * @dev Check if a price is stale
     */
    function isPriceStale(string memory asset) external view returns (bool) {
        if (!priceFeeds[asset].isActive) return true;
        
        PriceFeed memory feed = priceFeeds[asset];
        PythStructs.Price memory pythPrice = pyth.getPriceUnsafe(feed.priceId);
        
        return block.timestamp - pythPrice.publishTime > feed.maxStaleness;
    }

    /**
     * @dev Get price deviation between current and stored price
     */
    function getPriceDeviation(string memory asset) external view returns (uint256) {
        PriceData memory stored = latestPrices[asset];
        if (stored.price == 0) return 0;
        
        try this.getPrice(asset) returns (uint256 currentPrice) {
            if (currentPrice > stored.price) {
                return ((currentPrice - stored.price) * 10000) / stored.price;
            } else {
                return ((stored.price - currentPrice) * 10000) / stored.price;
            }
        } catch {
            return type(uint256).max;
        }
    }

    /**
     * @dev Get all supported assets
     */
    function getSupportedAssets() external view returns (string[] memory) {
        return supportedAssets;
    }

    /**
     * @dev Get price feed configuration
     */
    function getPriceFeedConfig(string memory asset) external view returns (
        bytes32 priceId,
        uint256 maxStaleness,
        uint8 targetDecimals,
        bool isActive,
        uint256 minPrice,
        uint256 maxPrice,
        string memory description
    ) {
        PriceFeed memory feed = priceFeeds[asset];
        return (
            feed.priceId,
            feed.maxStaleness,
            feed.targetDecimals,
            feed.isActive,
            feed.minPrice,
            feed.maxPrice,
            feed.description
        );
    }

    /**
     * @dev Get required fee for price updates
     */
    function getUpdateFee(bytes[] calldata priceUpdateData) external view returns (uint256) {
        return pyth.getUpdateFee(priceUpdateData);
    }

    /**
     * @dev Batch get multiple prices
     */
    function getMultiplePrices(string[] memory assets) external view returns (
        uint256[] memory prices,
        uint256[] memory timestamps,
        uint256[] memory confidences
    ) {
        prices = new uint256[](assets.length);
        timestamps = new uint256[](assets.length);
        confidences = new uint256[](assets.length);
        
        for (uint256 i = 0; i < assets.length; i++) {
            try this.getPriceData(assets[i]) returns (
                uint256 price,
                uint256 timestamp,
                uint256 confidence,
                bool
            ) {
                prices[i] = price;
                timestamps[i] = timestamp;
                confidences[i] = confidence;
            } catch {
                prices[i] = 0;
                timestamps[i] = 0;
                confidences[i] = type(uint256).max;
            }
        }
    }

    // Circuit breaker functions
    function resetCircuitBreaker() external onlyOwner {
        circuitBreakerTripped = false;
        emit CircuitBreakerReset();
    }

    function setCircuitBreakerThreshold(uint256 threshold) external onlyOwner {
        require(threshold > 0 && threshold <= 5000, "Invalid threshold"); // Max 50%
        circuitBreakerThreshold = threshold;
    }

    // Emergency functions
    function emergencyPause() external onlyOwner {
        _pause();
    }

    function emergencyUnpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Emergency price function for testing/emergency (when paused)
     */
    function setEmergencyPrice(string memory asset, uint256 price) external onlyOwner {
        require(paused(), "Only available when paused");
        require(price > 0, "Invalid price");
        
        latestPrices[asset] = PriceData({
            price: price,
            timestamp: block.timestamp,
            confidence: 0,
            isStale: false
        });
        
        emit PriceUpdated(asset, price, block.timestamp, 0);
    }

    // Allow contract to receive ETH for Pyth fee payments
    receive() external payable {}
}