<script lang="ts">
	import '../app.css';
	let { children } = $props();
</script>

<div class="min-h-screen bg-[#0b0b0e] text-[#ffb86b] font-['Share_Tech_Mono',ui-monospace,monospace]">
	<link rel="preconnect" href="https://fonts.googleapis.com" />
	<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
	<link href="https://fonts.googleapis.com/css2?family=Share+Tech+Mono&display=swap" rel="stylesheet" />
  
	<header class="grid grid-cols-[auto_1fr_auto] items-center gap-3 px-4 py-3 border-b border-[#ffb86b]/40 bg-gradient-to-b from-[#111114] to-[#0b0b0e]">
	  <div class="w-2 h-2 bg-[#ffb86b] shadow-[0_0_10px_2px_rgba(255,184,107,0.8)]" aria-hidden="true"></div>
	  <div class="tracking-[0.25em] text-sm">// RETRO WORKBENCH</div>
	  <div class="text-[10px] opacity-80 tracking-[0.2em]">80s‑UI</div>
	</header>

{@render children()}
</div>