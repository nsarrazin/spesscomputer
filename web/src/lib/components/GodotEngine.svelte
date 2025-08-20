<script lang="ts">
	import { onMount } from 'svelte';
	import { fade } from 'svelte/transition';

	// Props
	let { onEngineReady = null }: { onEngineReady?: ((engine: any) => void) | null } = $props();

	// State
	let canvasEl: HTMLCanvasElement;
	let wrapEl: HTMLDivElement;
	let isEngineLoading = $state(true);
	let loadingProgress = $state(0);
	let loadingCurrent = $state(0);
	let loadingTotal = $state(0);
	let engine: any = null;
	let resizeObserver: ResizeObserver | null = null;

	onMount(() => {
		// Initialize Godot engine after a short delay to ensure canvas is ready
		setTimeout(() => {
			initGodotEngine();
		}, 100);

		// Set up canvas resizing
		setupCanvasResizing();

		// Cleanup on unmount
		return () => {
			cleanupEngine();
			if (resizeObserver) {
				resizeObserver.disconnect();
			}
			window.removeEventListener('resize', resizeCanvas);
		};
	});

	function cleanupEngine() {
		console.log('Cleaning up Godot engine...');
		
		// Reset loading state
		isEngineLoading = true;
		loadingProgress = 0;
		loadingCurrent = 0;
		loadingTotal = 0;
		
		// Cleanup engine instance
		if (engine) {
			try {
				// Try to call cleanup methods if they exist
				if (typeof engine.delete === 'function') {
					engine.delete();
				}
				if (typeof engine.destroy === 'function') {
					engine.destroy();
				}
				if (typeof engine.quit === 'function') {
					engine.quit();
				}
			} catch (error) {
				console.warn('Error during engine cleanup:', error);
			}
			
			// Clear the engine reference
			engine = null;
		}

		// Clear canvas
		if (canvasEl) {
			try {
				// Clear canvas context
				const ctx = canvasEl.getContext('webgl2') || canvasEl.getContext('webgl');
				if (ctx) {
					ctx.clear(ctx.COLOR_BUFFER_BIT | ctx.DEPTH_BUFFER_BIT);
				}
				
				// Reset canvas size
				canvasEl.width = 0;
				canvasEl.height = 0;
			} catch (error) {
				console.warn('Error clearing canvas:', error);
			}
		}

		// Force garbage collection if available (development)
		if (typeof window.gc === 'function') {
			window.gc();
		}
		
		console.log('Godot engine cleanup completed');
	}

	function setupCanvasResizing() {
		if (!wrapEl || !canvasEl) return;

		// Initial resize
		resizeCanvas();

		// Set up ResizeObserver to watch for container size changes
		resizeObserver = new ResizeObserver(() => {
			resizeCanvas();
		});
		resizeObserver.observe(wrapEl);

		// Also listen for window resize as backup
		window.addEventListener('resize', resizeCanvas);
	}

	function resizeCanvas() {
		if (!canvasEl || !wrapEl) return;

		const rect = wrapEl.getBoundingClientRect();
		const dpr = window.devicePixelRatio || 1;

		// Set the display size (CSS pixels)
		canvasEl.style.width = rect.width + 'px';
		canvasEl.style.height = rect.height + 'px';

		// Set the actual size in memory (scaled for high-DPI displays)
		canvasEl.width = rect.width * dpr;
		canvasEl.height = rect.height * dpr;

		// Notify the Godot engine if it's running
		if (engine && engine.requestDisplayRefresh) {
			engine.requestDisplayRefresh();
		}
	}

	async function initGodotEngine() {
		try {
			// Wait for Engine to be available
			await waitForEngine();

			await navigator.serviceWorker.register('/SpessComputer.service.worker.js', { scope: '/' });

			navigator.serviceWorker.controller?.postMessage('clear');

			// Wait for canvas to be available
			if (!canvasEl) {
				console.error('Canvas element not available');
				return;
			}

			// Use the same config as the original Godot export
			const GODOT_CONFIG = {
				args: [],
				canvasResizePolicy: 0,
				ensureCrossOriginIsolationHeaders: true,
				executable: 'SpessComputer',
				experimentalVK: false,
				fileSizes: { 'SpessComputer.pck': 5892736, 'SpessComputer.wasm': 1648133 },
				focusCanvas: true,
				gdextensionLibs: ['godot_6502.wasm'],
				serviceWorker: 'SpessComputer.service.worker.js'
			};

			// Check for missing browser features (same as original HTML)
			// @ts-ignore
			const missing = Engine.getMissingFeatures({
				threads: true // GODOT_THREADS_ENABLED
			});

			if (missing.length !== 0) {
				console.error('Missing required browser features:', missing);
				throw new Error('Missing browser features: ' + missing.join(', '));
			}

			// @ts-ignore
			engine = new Engine(GODOT_CONFIG);

			// Set up logging functions
			function print(text: string) {
				console.log('[Godot]', text);
			}
			function printError(text: string) {
				console.error('[Godot Error]', text);
			}
			function onProgress(current: number, total: number) {
				loadingCurrent = current;
				loadingTotal = total;
				if (total > 0) {
					loadingProgress = Math.round((current / total) * 100);
					console.log(
						`Loading: ${current} of ${total} bytes (${loadingProgress}%)`
					);
				} else {
					loadingProgress = 0;
					console.log(`Loading: ${current} bytes`);
				}
			}

			console.log('Starting game...');
			await engine.startGame({
				canvas: canvasEl,
				onPrint: print,
				onPrintError: printError,
				onProgress: onProgress
			});
			console.log('Game started successfully!');

			// Ensure canvas is properly sized after engine initialization
			resizeCanvas();

			// Hide loading indicator
			isEngineLoading = false;

			// Notify parent component that engine is ready
			if (onEngineReady) {
				onEngineReady(engine);
			}
		} catch (error) {
			console.error('Failed to start Godot engine:', error);
			// Hide loading indicator even on error
			isEngineLoading = false;
		}
	}

	function waitForEngine(): Promise<void> {
		return new Promise((resolve, reject) => {
			// Check if Engine is already available
			// @ts-ignore
			if (typeof Engine !== 'undefined') {
				resolve();
				return;
			}

			// Wait for script to load
			let attempts = 0;
			const maxAttempts = 100; // 10 seconds max

			const checkEngine = () => {
				// @ts-ignore
				if (typeof Engine !== 'undefined') {
					resolve();
				} else if (attempts >= maxAttempts) {
					reject(new Error('Engine script failed to load'));
				} else {
					attempts++;
					setTimeout(checkEngine, 100);
				}
			};

			checkEngine();
		});
	}

	// Expose the engine instance for external access
	export function getEngine() {
		return engine;
	}
</script>

<div class="relative h-[60vh] lg:h-[78vh]" bind:this={wrapEl}>
	<canvas
		id="canvas"
		class="absolute inset-0 block"
		bind:this={canvasEl}
		aria-label="main canvas"
	></canvas>

	{#if isEngineLoading}
		<div
			class="absolute inset-0 flex items-center justify-center bg-[#131318]/90 backdrop-blur-sm"
			in:fade={{ duration: 200 }}
			out:fade={{ duration: 300 }}
		>
			<div class="flex flex-col items-center gap-4 text-[#ffb86b]">
				<div class="relative">
					<!-- Spinning loading ring -->
					<div class="h-12 w-12 rounded-full border-2 border-[#ffb86b]/20"></div>
					<div
						class="absolute inset-0 h-12 w-12 animate-spin rounded-full border-2 border-transparent border-t-[#ffb86b]"
					></div>
				</div>
				<div class="text-center">
					<div class="font-mono text-sm tracking-[0.2em]">INITIALIZING</div>
					<div class="mt-1 text-xs tracking-[0.15em] text-[#ffb86b]/70">VISUAL LINK</div>
					
					{#if loadingTotal > 0}
						<div class="mt-3 space-y-2">
							<div class="text-xs font-mono tracking-wider text-[#ffb86b]/80">
								{loadingProgress}%
							</div>
							<div class="relative h-1 w-32 rounded-full bg-[#ffb86b]/20">
								<div 
									class="absolute inset-y-0 left-0 rounded-full bg-[#ffb86b] transition-all duration-300 ease-out"
									style="width: {loadingProgress}%"
								></div>
							</div>
						</div>
					{/if}
				</div>
			</div>
		</div>
	{/if}
</div>

<style>
	/* Canvas styling */
	#canvas {
		display: block;
		outline: none;
		background: transparent;
	}
</style> 