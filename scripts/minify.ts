import { minify } from "terser";
import fs from "fs";
import path from "path";

// ---------------- CONFIGURATION ----------------
const FILES: Record<string, string> = {
  matchInit: "./scripts/match-init.js",
  scoreFetch: "./scripts/request-score.js",
  settlement: "./scripts/request-settlement.js",
};

// ---------------- MINIFICATION LOGIC ----------------
async function minifyFile(filePath: string): Promise<string> {
  const absolutePath = path.resolve(filePath);
  
  if (!fs.existsSync(absolutePath)) {
    console.error(`❌ File not found: ${absolutePath}`);
    process.exit(1);
  }

  const code = fs.readFileSync(absolutePath, "utf8");

  try {
    const result = await minify(code, {
      ecma: 2020,     // ✅ Fix 1: Enable modern syntax (ES2020+)
      module: true,   // ✅ Fix 2: Enable Top-Level Await support
      parse: {
        bare_returns: true // ✅ Fix 3: Allow 'return' outside functions
      },
      mangle: {
        toplevel: true, 
        reserved: ["ethers", "args", "Functions"], // Protect Chainlink globals
      },
      compress: {
        sequences: true,
        dead_code: true,
        conditionals: true,
        booleans: true,
        unused: true,
        if_return: true,
        join_vars: true,
        drop_console: true,
        module: true // specific compress option for top-level await
      },
    });

    if (!result.code) {
      throw new Error(`Minification resulted in empty code for ${filePath}`);
    }

    return result.code;
    
  } catch (error) {
    console.error(`❌ Error minifying ${filePath}:`);
    throw error;
  }
}

// ---------------- RUNNER ----------------
async function main() {
  console.log("🚀 Starting Minification...\n");
  
  const output: Record<string, string> = {};

  for (const [key, filePath] of Object.entries(FILES)) {
    try {
        const minified = await minifyFile(filePath);
        output[key] = minified;
        
        const originalSize = fs.readFileSync(filePath).length;
        const savings = Math.round((1 - minified.length / originalSize) * 100);

        console.log(`✅ ${key}:`);
        console.log(`   Original: ${originalSize} bytes`);
        console.log(`   Minified: ${minified.length} bytes`);
        console.log(`   Savings:  ${savings}%\n`);
    } catch (e) {
        // Skip this file but continue others
        console.log(`Skipping ${key} due to error.\n`);
    }
  }

  // OPTION: Print to Console in a format ready for Solidity
  console.log("📋 COPY THESE STRINGS INTO SOLIDITY:\n");
  
  if (output.matchInit) {
    console.log(`// Match Init Script`);
    console.log(`return "${output.matchInit.replace(/"/g, '\\"')}";\n`); 
  }

  if (output.scoreFetch) {
    console.log(`// Score Fetch Script`);
    console.log(`return "${output.scoreFetch.replace(/"/g, '\\"')}";\n`);
  }

  if (output.settlement) {
    console.log(`// Settlement Script`);
    console.log(`return "${output.settlement.replace(/"/g, '\\"')}";\n`);
  }

  // Save to JSON
  const outputPath = "./scripts/minified-scripts.json";
  fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));
  console.log(`💾 Saved minified scripts to ${outputPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});