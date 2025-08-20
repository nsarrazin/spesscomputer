<script lang="ts">
	import '../app.css';
	let { children } = $props();
</script>

<div class="min-h-screen bg-[#0b0b0e] text-[#ffb86b] font-mono">
	<header class="grid grid-cols-[auto_1fr_auto] items-center gap-3 px-4 py-3 border-b border-[#ffb86b]/40 bg-gradient-to-b from-[#111114] to-[#0b0b0e]">
	  <div class="w-2 h-2 bg-[#ffb86b] shadow-[0_0_10px_2px_rgba(255,184,107,0.8)]" aria-hidden="true"></div>
	  <div class="tracking-[0.25em] text-sm">// SPESSCOMPUTER</div>
	  <div class="text-[10px] opacity-80 tracking-[0.2em]">6502</div>
	</header>

{@render children()}
</div>