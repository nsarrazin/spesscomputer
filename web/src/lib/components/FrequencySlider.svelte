<script lang="ts">
	import { onMount } from 'svelte';
	import { appState } from '$lib/AppState.svelte';

	// No props needed - frequency comes from AppState

	// Slider state for UI (derived from AppState frequency)
	let sliderValue = $state(0);

	async function handlePause() {
		try {
			await WebHelper.pause();
			appState.isPaused = true;
		} catch (err) {
			console.error('Failed to pause', err);
		}
	}

	async function handleResume() {
		try {
			await WebHelper.resume();
			appState.isPaused = false;
		} catch (err) {
			console.error('Failed to resume', err);
		}
	}

	async function handleStep() {
		try {
			await WebHelper.step();
		} catch (err) {
			console.error('Failed to step', err);
		}
	}
	
	const FREQ_MIN = 1;
	const FREQ_MAX = 50000;
	const FREQ_PRESETS = [1, 10, 100, 5000, 50000];

	function sliderToFreq(val: number): number {
		const t = Math.max(0, Math.min(1, val / 1000));
		const logMin = Math.log10(FREQ_MIN);
		const logMax = Math.log10(FREQ_MAX);
		const logF = logMin + t * (logMax - logMin);
		let f = Math.pow(10, logF);
		// Snap to presets within ~4%
		for (const p of FREQ_PRESETS) {
			if (Math.abs(f - p) / p < 0.04) {
				f = p;
				break;
			}
		}
		return Math.max(FREQ_MIN, Math.min(FREQ_MAX, Math.round(f)));
	}

	function freqToSlider(freq: number): number {
		const f = Math.max(FREQ_MIN, Math.min(FREQ_MAX, freq));
		const logMin = Math.log10(FREQ_MIN);
		const logMax = Math.log10(FREQ_MAX);
		const t = (Math.log10(f) - logMin) / (logMax - logMin);
		return Math.round(t * 1000);
	}

	function formatFrequency(freq: number): string {
		if (freq >= 1000) {
			const khz = freq / 1000;
			return `${khz % 1 === 0 ? khz.toFixed(0) : khz.toFixed(2)} kHz`;
		}
		return `${freq} Hz`;
	}

	function onFrequencyInput(e: Event) {
		const target = e.currentTarget as HTMLInputElement;
		sliderValue = Number(target.value);
		const f = sliderToFreq(sliderValue);
		// Light thumb snapping to nearby presets
		const targetSlider = freqToSlider(f);
		if (Math.abs(targetSlider - sliderValue) <= 6) {
			sliderValue = targetSlider;
		}
		
		// Update AppState frequency
		appState.setFrequency(f);
		
		// Update emulator frequency continuously during drag
		try {
			// Do not await to keep UI responsive
			WebHelper.setFrequency(f);
		} catch (err) {
			console.error('Failed to set frequency', err);
		}
	}

	// Initialize slider position based on AppState frequency
	onMount(() => {
		console.log('FrequencySlider onMount, appState.frequency:', appState.frequency);
		sliderValue = freqToSlider(appState.frequency);
		console.log('Set sliderValue to:', sliderValue);
	});

	$effect(() => {
		// Keep slider position in sync with AppState frequency changes
		console.log('FrequencySlider effect, appState.frequency changed to:', appState.frequency);
		sliderValue = freqToSlider(appState.frequency);
		console.log('Updated sliderValue to:', sliderValue);
	});
</script>

<div class="grid gap-2">
	<div class="mb-1 flex items-center justify-between">
		<div class="flex gap-2">
			{#if !appState.isPaused}
				<button
					onclick={handlePause}
					class="border border-[#ffb86b]/40 bg-[#0f0f12] px-2 py-1 text-[11px] tracking-[0.18em] text-[#ffb86b]/80 shadow-[inset_0_0_0_1px_rgba(255,184,107,0.35)] hover:text-[#ffb86b]"
					aria-label="Pause"
					type="button"
				>
					<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" class="h-4 w-4" fill="currentColor" aria-hidden="true">
						<rect x="6" y="4" width="4" height="16" rx="1" />
						<rect x="14" y="4" width="4" height="16" rx="1" />
					</svg>
				</button>
			{:else}
				<button
					onclick={handleResume}
					class="border border-[#ffb86b]/40 bg-[#0f0f12] px-2 py-1 text-[11px] tracking-[0.18em] text-[#ffb86b]/80 shadow-[inset_0_0_0_1px_rgba(255,184,107,0.35)] hover:text-[#ffb86b]"
					aria-label="Play"
					type="button"
				>
					<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" class="h-4 w-4" fill="currentColor" aria-hidden="true">
						<polygon points="8,5 8,19 19,12" />
					</svg>
				</button>
				<button
					onclick={handleStep}
					class="border border-[#ffb86b]/40 bg-[#0f0f12] px-2 py-1 text-[11px] tracking-[0.18em] text-[#ffb86b]/80 shadow-[inset_0_0_0_1px_rgba(255,184,107,0.35)] hover:text-[#ffb86b]"
					aria-label="Step"
					type="button"
				>
					<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" class="h-4 w-4" fill="currentColor" aria-hidden="true">
						<rect x="5" y="5" width="2" height="14" rx="1" />
						<polygon points="9,5 9,19 20,12" />
					</svg>
				</button>
			{/if}
		</div>
	</div>
	<div class="flex items-center justify-between text-xs tracking-[0.15em] text-[#ffb86b]/80">
		<span>CPU FREQUENCY</span>
		<span class="font-mono">{formatFrequency(appState.frequency)}</span>
	</div>
	<input
		type="range"
		min="0"
		max="1000"
		step="1"
		bind:value={sliderValue}
		oninput={onFrequencyInput}
		list="freq-ticks"
		class="w-full accent-[#ffb86b]"
	/>
	<datalist id="freq-ticks">
		<option value={freqToSlider(1)} label="1 Hz"></option>
		<option value={freqToSlider(10)} label="10 Hz"></option>
		<option value={freqToSlider(100)} label="100 Hz"></option>
		<option value={freqToSlider(5000)} label="5 kHz"></option>
		<option value={freqToSlider(50000)} label="50 kHz"></option>
	</datalist>
	<div class="flex justify-between text-[10px] font-mono text-[#ffb86b]/60">
		<span>1 Hz</span>
		<span>10 Hz</span>
		<span>100 Hz</span>
		<span>5 kHz</span>
		<span>50 kHz</span>
	</div>
</div> 