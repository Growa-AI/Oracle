// backend/package_generator.js
const sharp = require('sharp');
const d3 = require('d3');
const { createCanvas } = require('canvas');
const crypto = require('crypto');
const fs = require('fs').promises;

class PackageGenerator {
    constructor() {
        this.imageWidth = 800;
        this.imageHeight = 400;
        this.padding = 50;
    }

    async generateDataPackage(rawData, metadata) {
        try {
            // Process raw data
            const processedData = this.processData(rawData);

            // Generate visualizations
            const visualizations = await this.generateVisualizations(rawData, processedData);

            // Create package metadata
            const packageMetadata = this.createPackageMetadata(metadata, rawData);

            // Assemble package
            const dataPackage = {
                raw_data: rawData,
                processed_data: processedData,
                metadata: packageMetadata,
                visualizations: visualizations
            };

            // Store package
            await this.storePackage(dataPackage);

            return dataPackage;
        } catch (error) {
            console.error('Error generating package:', error);
            throw error;
        }
    }

    processData(rawData) {
        const values = rawData.map(r => r.value);
        return {
            min: Math.min(...values),
            max: Math.max(...values),
            avg: values.reduce((a, b) => a + b, 0) / values.length,
            median: this.calculateMedian(values)
        };
    }

    async generateVisualizations(rawData, processedData) {
        const visualizations = [];

        // Generate line chart
        const lineChart = await this.generateLineChart(rawData);
        visualizations.push({
            type_: "chart",
            format: "svg",
            data: lineChart,
            parameters: [
                ["chartType", "line"],
                ["width", this.imageWidth.toString()],
                ["height", this.imageHeight.toString()]
            ]
        });

        // Generate heatmap if location data is available
        if (rawData.some(d => d.location)) {
            const heatmap = await this.generateHeatmap(rawData);
            visualizations.push({
                type_: "map",
                format: "png",
                data: heatmap,
                parameters: [
                    ["mapType", "heatmap"],
                    ["width", this.imageWidth.toString()],
                    ["height", this.imageHeight.toString()]
                ]
            });
        }

        return visualizations;
    }

    async generateLineChart(data) {
        const canvas = createCanvas(this.imageWidth, this.imageHeight);
        const context = canvas.getContext('2d');

        // Set up scales
        const xScale = d3.scaleTime()
            .domain(d3.extent(data, d => d.created_at))
            .range([this.padding, this.imageWidth - this.padding]);

        const yScale = d3.scaleLinear()
            .domain([d3.min(data, d => d.value), d3.max(data, d => d.value)])
            .range([this.imageHeight - this.padding, this.padding]);

        // Draw axes
        const xAxis = d3.axisBottom(xScale);
        const yAxis = d3.axisLeft(yScale);

        // Create SVG
        const svg = `
            <svg width="${this.imageWidth}" height="${this.imageHeight}">
                <style>
                    .line { fill: none; stroke: #2196F3; stroke-width: 2; }
                    .axis { font: 10px sans-serif; }
                    .grid { stroke: #ddd; stroke-width: 0.5; }
                </style>
                <g class="grid">${this.createGrid(xScale, yScale)}</g>
                <path class="line" d="${this.createLinePath(data, xScale, yScale)}"/>
                <g class="x-axis" transform="translate(0,${this.imageHeight - this.padding})">${xAxis}</g>
                <g class="y-axis" transform="translate(${this.padding},0)">${yAxis}</g>
            </svg>
        `;

        return svg;
    }

    async generateHeatmap(data) {
        const points = data.map(d => ({
            lat: d.location.latitude,
            lng: d.location.longitude,
            value: d.value
        }));

        // Create heatmap using sharp
        const heatmap = await sharp({
            create: {
                width: this.imageWidth,
                height: this.imageHeight,
                channels: 4,
                background: { r: 255, g: 255, b: 255, alpha: 0 }
            }
        })
        .composite(this.generateHeatmapLayers(points))
        .png()
        .toBuffer();

        return heatmap.toString('base64');
    }

    createPackageMetadata(metadata, rawData) {
        const dataHash = this.generateHash(JSON.stringify(rawData));
        
        return {
            package_id: `pkg_${Date.now()}_${dataHash.slice(0, 8)}`,
            created_at: Date.now(),
            expires_at: Date.now() + (30 * 24 * 60 * 60 * 1000), // 30 days
            data_hash: dataHash,
            checksum: this.generateChecksum(rawData),
            schema_version: 1,
            source_device: metadata.device_id || 'unknown',
            data_type: metadata.data_type || 'sensor',
            sample_rate: metadata.sample_rate || 1,
            unit: metadata.unit || 'unit',
            location: metadata.location || null
        };
    }

    async storePackage(dataPackage) {
        const filename = `packages/${dataPackage.metadata.package_id}.json`;
        await fs.writeFile(filename, JSON.stringify(dataPackage, null, 2));
    }

    // Helper functions
    calculateMedian(values) {
        const sorted = [...values].sort((a, b) => a - b);
        const mid = Math.floor(sorted.length / 2);
        return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
    }

    createGrid(xScale, yScale) {
        // Create grid lines
        const xTicks = xScale.ticks();
        const yTicks = yScale.ticks();
        
        let gridLines = '';
        
        // Vertical grid lines
        xTicks.forEach(tick => {
            const x = xScale(tick);
            gridLines += `<line x1="${x}" y1="${this.padding}" x2="${x}" y2="${this.imageHeight - this.padding}"/>`;
        });
        
        // Horizontal grid lines
        yTicks.forEach(tick => {
            const y = yScale(tick);
            gridLines += `<line x1="${this.padding}" y1="${y}" x2="${this.imageWidth - this.padding}" y2="${y}"/>`;
        });
        
        return gridLines;
    }

    createLinePath(data, xScale, yScale) {
        const line = d3.line()
            .x(d => xScale(d.created_at))
            .y(d => yScale(d.value));
        
        return line(data);
    }

    generateHeatmapLayers(points) {
        // Generate heatmap layers with different intensities
        const layers = [];
        const intensities = [0.1, 0.3, 0.5, 0.7, 0.9];
        
        intensities.forEach(intensity => {
            const layer = this.createHeatmapLayer(points, intensity);
            layers.push({
                input: layer,
                blend: 'multiply'
            });
        });
        
        return layers;
    }

    generateHash(data) {
        return crypto.createHash('sha256').update(data).digest('hex');
    }

    generateChecksum(data) {
        return crypto.createHash('md5').update(JSON.stringify(data)).digest('hex');
    }
}

module.exports = PackageGenerator;
