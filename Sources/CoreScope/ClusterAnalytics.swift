import Foundation

// MARK: - Hardware Cluster Subsystem

/// Specific compute or fabric cluster on Apple Silicon.
enum HardwareCluster: String, CaseIterable, Identifiable, Sendable, Comparable {
    case pCoreCluster = "P-Core Cluster"
    case eCoreCluster = "E-Core Cluster"
    case gpu = "GPU Cores"
    case socFabric = "SoC / Fabric / ANE"
    case unmapped = "Unmapped Die Channel"

    var id: String { rawValue }

    static func < (lhs: HardwareCluster, rhs: HardwareCluster) -> Bool {
        let order: [HardwareCluster] = [.pCoreCluster, .eCoreCluster, .gpu, .socFabric, .unmapped]
        let lIdx = order.firstIndex(of: lhs) ?? 99
        let rIdx = order.firstIndex(of: rhs) ?? 99
        return lIdx < rIdx
    }
}

// MARK: - Mapping Confidence

/// Source and certainty level for sensor-to-hardware mapping.
enum MappingConfidence: String, Sendable, Equatable {
    /// Mapping directly verified from hardware service properties or vendor descriptors.
    case verifiedHardwareMetadata = "Verified Hardware Descriptor"
    /// Heuristic mapping based on published architectural research, but lacking direct OS metadata.
    case heuristicResearch = "Architectural Heuristic"
    /// No verifiable mapping exists on this hardware platform; channel is kept unmapped.
    case unsupported = "Unsupported on Platform"
}

// MARK: - Sensor Descriptor

/// An authentic sensor record in the hardware registry.
struct SensorDescriptor: Identifiable, Sendable, Equatable {
    /// Unique identifier for this channel instance.
    let id: String
    /// Authentic hardware-reported name (e.g. "PMU tdie1", "PMU2 tdie8").
    let name: String
    /// Validated functional subsystem category (e.g. .siliconDie, .deviceNode).
    let category: SensorCategory
    /// Attributed hardware cluster, or .unmapped if no verified attribution exists.
    let cluster: HardwareCluster
    /// Source or confidence level of the cluster mapping.
    let confidence: MappingConfidence
    /// Hardware location identifier from IOHIDService property, if available.
    let locationID: UInt32?
    /// Validated temperature in degrees Celsius (5–120 °C).
    let valueC: Double
    /// Unit string.
    let unit: String

    init(
        id: String,
        name: String,
        category: SensorCategory,
        cluster: HardwareCluster = .unmapped,
        confidence: MappingConfidence = .unsupported,
        locationID: UInt32? = nil,
        valueC: Double,
        unit: String = "°C"
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.cluster = cluster
        self.confidence = confidence
        self.locationID = locationID
        self.valueC = valueC
        self.unit = unit
    }

    /// Factory to convert a TemperatureReading into a SensorDescriptor using strict mapping rules.
    static func from(reading: TemperatureReading, locationID: UInt32? = nil) -> SensorDescriptor {
        let (cluster, confidence) = mapCluster(sensorName: reading.sensorName, category: reading.category)
        return SensorDescriptor(
            id: reading.id,
            name: reading.sensorName,
            category: reading.category,
            cluster: cluster,
            confidence: confidence,
            locationID: locationID,
            valueC: reading.temperatureC,
            unit: "°C"
        )
    }

    /// Evaluates whether a raw sensor name provides verified hardware cluster attribution.
    ///
    /// Principle: Generic numbered PMU channels ("PMU tdie1", "PMU2 tdie8") DO NOT specify
    /// core or cluster assignment in their descriptors. We refuse to invent P/E/GPU mappings
    /// without verifiable evidence. Only channels with authentic sub-domain descriptors
    /// (e.g. "pdie", "edie", "gdie", "cpu-p-core", "gpu-core") receive cluster attribution.
    static func mapCluster(sensorName: String, category: SensorCategory) -> (HardwareCluster, MappingConfidence) {
        guard category == .siliconDie else {
            // Only silicon die sensors can belong to compute clusters
            return (.unmapped, .unsupported)
        }

        let lower = sensorName.lowercased()

        // Authentic cluster descriptors (e.g. specific PMU channels or future SoC telemetry)
        if lower.contains("pdie") || lower.contains("p-core") || lower.contains("perf-core") {
            return (.pCoreCluster, .verifiedHardwareMetadata)
        } else if lower.contains("edie") || lower.contains("e-core") || lower.contains("eff-core") {
            return (.eCoreCluster, .verifiedHardwareMetadata)
        } else if lower.contains("gdie") || lower.contains("gpu die") || lower.contains("gpu-core") {
            return (.gpu, .verifiedHardwareMetadata)
        } else if lower.contains("soc die") || lower.contains("fabric") || lower.contains("ane die") {
            return (.socFabric, .verifiedHardwareMetadata)
        }

        // Generic numbered PMU die channels (e.g. "PMU tdie1", "PMU2 tdie8") on M4 / Apple Silicon
        // Lack direct OS cluster descriptors. Keep strictly unmapped.
        return (.unmapped, .unsupported)
    }
}

// MARK: - Cluster Measurement

/// Compact summary of a single hardware cluster's thermal telemetry.
struct ClusterMeasurement: Sendable, Equatable {
    let cluster: HardwareCluster
    /// Whether any contributing sensors were verified for this cluster.
    let isAvailable: Bool
    /// Mean temperature across verified contributing sensors in °C, or nil.
    let averageC: Double?
    /// Peak temperature observed in this cluster, or nil.
    let peakC: Double?
    /// Name of the peak contributing sensor.
    let peakSensorName: String?
    /// Number of verified sensors contributing to this cluster.
    let sensorCount: Int
    /// Explanatory note or unavailability reason.
    let note: String

    init(
        cluster: HardwareCluster,
        isAvailable: Bool,
        averageC: Double? = nil,
        peakC: Double? = nil,
        peakSensorName: String? = nil,
        sensorCount: Int = 0,
        note: String
    ) {
        self.cluster = cluster
        self.isAvailable = isAvailable
        self.averageC = averageC
        self.peakC = peakC
        self.peakSensorName = peakSensorName
        self.sensorCount = sensorCount
        self.note = note
    }

    /// Formatted average string or "Unavailable".
    var formattedAverage: String {
        if let avg = averageC {
            return String(format: "%.1f °C", avg)
        }
        return "Unavailable"
    }

    /// Formatted peak string or "Unavailable".
    var formattedPeak: String {
        if let peak = peakC {
            return String(format: "%.1f °C", peak)
        }
        return "Unavailable"
    }
}

// MARK: - Sensor Registry

/// Comprehensive sensor registry managing authenticated hardware channels,
/// cluster breakdowns, and category conservation guarantees.
struct SensorRegistry: Sendable, Equatable {
    let descriptors: [SensorDescriptor]

    init(descriptors: [SensorDescriptor] = []) {
        self.descriptors = descriptors
    }

    init(from readings: [TemperatureReading]) {
        self.descriptors = readings.map { SensorDescriptor.from(reading: $0) }
    }

    static func build(from readings: [TemperatureReading]) -> SensorRegistry {
        SensorRegistry(from: readings)
    }

    /// Validated cluster measurement for a given domain.
    func clusterMeasurement(for cluster: HardwareCluster) -> ClusterMeasurement {
        guard cluster != .unmapped else {
            let unmapped = descriptors.filter { $0.cluster == .unmapped && $0.category == .siliconDie }
            let count = unmapped.count
            return ClusterMeasurement(
                cluster: .unmapped,
                isAvailable: count > 0,
                averageC: count > 0 ? (unmapped.reduce(0.0) { $0 + $1.valueC } / Double(count)) : nil,
                sensorCount: count,
                note: "\(count) unmapped die channels"
            )
        }

        // Filter strictly by cluster attribution and siliconDie category
        let clusterSensors = descriptors.filter { $0.cluster == cluster && $0.category == .siliconDie }

        guard !clusterSensors.isEmpty else {
            let reason: String
            switch cluster {
            case .pCoreCluster:
                reason = "PMU tdie channels lack public P-core descriptors on this Mac"
            case .eCoreCluster:
                reason = "PMU tdie channels lack public E-core descriptors on this Mac"
            case .gpu:
                reason = "PMU tdie channels lack public GPU descriptors on this Mac"
            case .socFabric:
                reason = "PMU tdie channels lack public Fabric/ANE descriptors on this Mac"
            case .unmapped:
                reason = "No unmapped sensors"
            }
            return ClusterMeasurement(
                cluster: cluster,
                isAvailable: false,
                averageC: nil,
                peakC: nil,
                peakSensorName: nil,
                sensorCount: 0,
                note: reason
            )
        }

        let sum = clusterSensors.reduce(0.0) { $0 + $1.valueC }
        let avg = sum / Double(clusterSensors.count)
        let peakSensor = clusterSensors.max(by: { $0.valueC < $1.valueC })

        return ClusterMeasurement(
            cluster: cluster,
            isAvailable: true,
            averageC: avg,
            peakC: peakSensor?.valueC,
            peakSensorName: peakSensor?.name,
            sensorCount: clusterSensors.count,
            note: "\(clusterSensors.count) verified channel\(clusterSensors.count == 1 ? "" : "s")"
        )
    }

    var pCoreCluster: ClusterMeasurement { clusterMeasurement(for: .pCoreCluster) }
    var eCoreCluster: ClusterMeasurement { clusterMeasurement(for: .eCoreCluster) }
    var gpuCluster: ClusterMeasurement { clusterMeasurement(for: .gpu) }
    var socFabricCluster: ClusterMeasurement { clusterMeasurement(for: .socFabric) }

    /// Number of unmapped die channels
    var unmappedCount: Int {
        descriptors.filter { $0.cluster == .unmapped && $0.category == .siliconDie }.count
    }

    /// Whether any specific cluster was verified.
    var hasVerifiedClusterMappings: Bool {
        descriptors.contains { $0.cluster != .unmapped && $0.confidence == .verifiedHardwareMetadata }
    }
}
