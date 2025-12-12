<script setup lang="ts">
import { ref, reactive, computed, onMounted, watch } from 'vue';
import type { Grado, DesempenoItem } from '../types';
import desempenosService from '../services/api';
import ComboBox from './ComboBox.vue';
import * as d3 from 'd3';

// --- State ---
const grados = ref<Grado[]>([]);
const selectedGradoId = ref<number | null>(null);
const loadingGrados = ref(false);

// Desempeños fetched from DB for the selected grade
const availableDesempenos = ref<DesempenoItem[]>([]);
const loadingDesempenos = ref(false);

const activeTab = ref<'config' | 'registro' | 'resultados'>('config');

// Configuración de Desempeños
interface PreguntaConfig {
    descripcion: string; // filled from DB desempeño or manual
    desempenoId: number | null; // ID from DB
    clave: string;
}

interface NivelConfig {
    nombre: string;
    descripcion: string;
    preguntas: PreguntaConfig[];
    color: string;
    bg: string;
    key: string;
}

// Initial State matching the user's JS
const niveles = reactive<Record<string, NivelConfig>>({
    'pre-inicio': {
        nombre: 'PRE INICIO',
        descripcion: '(Literal, Inferencial o Crítico)',
        color: '#ef4444',
        bg: 'rgba(239, 68, 68, 0.15)',
        key: 'pre-inicio',
        preguntas: []
    },
    'inicio': {
        nombre: 'INICIO',
        descripcion: '(Literal)',
        color: '#f97316',
        bg: 'rgba(249, 115, 22, 0.15)',
        key: 'inicio',
        preguntas: []
    },
    'proceso': {
        nombre: 'EN PROCESO',
        descripcion: '(Inferencial)',
        color: '#eab308',
        bg: 'rgba(234, 179, 8, 0.15)',
        key: 'proceso',
        preguntas: []
    },
    'satisfactorio': {
        nombre: 'SATISFACTORIO',
        descripcion: '(Crítico)',
        color: '#22c55e',
        bg: 'rgba(34, 197, 94, 0.15)',
        key: 'satisfactorio',
        preguntas: []
    },
    'destacado': {
        nombre: 'LOGRO DESTACADO',
        descripcion: '(Literal, Inferencial o Crítico)',
        color: '#6366f1',
        bg: 'rgba(99, 102, 241, 0.15)',
        key: 'destacado',
        preguntas: []
    }
});

const competencia = ref('Lee diversos tipos de textos escritos en su lengua materna');

// Students Data
interface Estudiante {
    nombre: string;
    respuestas: Record<string, string[]>; // key is nivel key, value is array of answers
    puntajes?: Record<string, { correctas: number, total: number, porcentaje: number }>;
    nivelFinal?: string | null;
}

const estudiantes = ref<Estudiante[]>([]);

// Chart reference
const chartContainer = ref<HTMLDivElement | null>(null);

// --- Computed ---
const gradosPorNivel = computed(() => {
    return {
        primaria: grados.value.filter(g => g.nivel === 'primaria'),
        secundaria: grados.value.filter(g => g.nivel === 'secundaria')
    };
});

const gradoOptions = computed(() => {
    const options: { id: number; label: string; group: string }[] = [];
    gradosPorNivel.value.primaria.forEach(g => {
        options.push({ id: g.id, label: `${g.numero}° Primaria`, group: 'Primaria' });
    });
    gradosPorNivel.value.secundaria.forEach(g => {
        options.push({ id: g.id, label: `${g.numero}° Secundaria`, group: 'Secundaria' });
    });
    return options;
});

const desempenoOptions = computed(() => {
    return availableDesempenos.value.map(d => ({
        id: d.id,
        label: `${d.codigo} - ${d.descripcion.substring(0, 100)}${d.descripcion.length > 100 ? '...' : ''}`,
        group: d.capacidad_tipo ? d.capacidad_tipo.toUpperCase() : 'General'
    }));
});

// Stats Computed
const stats = computed(() => {
    const s = {
        total: estudiantes.value.length,
        'pre-inicio': 0,
        'inicio': 0,
        'proceso': 0,
        'satisfactorio': 0,
        'destacado': 0
    };

    estudiantes.value.forEach(est => {
        if (est.nivelFinal) {
            const nivel = est.nivelFinal.toLowerCase().replace(/ /g, '-').replace('en-', '');
            // map back to keys if strictly needed, but let's normalize
            if (nivel === 'pre-inicio') s['pre-inicio']++;
            else if (nivel === 'inicio') s['inicio']++;
            else if (nivel === 'proceso') s['proceso']++;
            else if (nivel === 'satisfactorio') s['satisfactorio']++;
            else if (nivel === 'destacado' || nivel === 'logro-destacado') s['destacado']++;
        }
    });
    return s;
});

// --- Methods ---

const loadGrados = async () => {
    loadingGrados.value = true;
    try {
        grados.value = await desempenosService.getGrados();
        if (grados.value.length > 0 && !selectedGradoId.value && grados.value[0]) {
            selectedGradoId.value = grados.value[0].id;
        }
    } catch (e) {
        console.error("Error loading degrees", e);
    } finally {
        loadingGrados.value = false;
    }
};

const loadDesempenos = async () => {
    if (!selectedGradoId.value) return;
    loadingDesempenos.value = true;
    try {
        availableDesempenos.value = await desempenosService.getDesempenosPorGrado(selectedGradoId.value);
    } catch (e) {
        console.error("Error loading performances", e);
    } finally {
        loadingDesempenos.value = false;
    }
};

watch(selectedGradoId, () => {
    // Clear all questions when grade changes
    Object.keys(niveles).forEach(key => {
        if (niveles[key]) {
            niveles[key].preguntas = [];
        }
    });
    // Load new desempeños
    loadDesempenos();
});

// Config Methods
const addPregunta = (nivelKey: string) => {
    if (niveles[nivelKey]) {
        niveles[nivelKey].preguntas.push({
            descripcion: '',
            desempenoId: null,
            clave: ''
        });
    }
};

const removePregunta = (nivelKey: string, index: number) => {
    if (niveles[nivelKey]) {
        niveles[nivelKey].preguntas.splice(index, 1);
    }
};

const onDesempenoSelect = (nivelKey: string, index: number, id: number | null) => {
    if (niveles[nivelKey]) {
        const preg = niveles[nivelKey].preguntas[index];
        if (preg) {
            preg.desempenoId = id;
            if (id) {
                const found = availableDesempenos.value.find(d => d.id === id);
                if (found) {
                    preg.descripcion = found.descripcion;
                }
            }
        }
    }
};

// Students Methods
const addEstudiante = () => {
    estudiantes.value.push({
        nombre: '',
        respuestas: {},
        puntajes: {},
        nivelFinal: null
    });
};

const removeEstudiante = (index: number) => {
    estudiantes.value.splice(index, 1);
};

const calcularResultados = () => {
    const nivelesKeys = ['pre-inicio', 'inicio', 'proceso', 'satisfactorio', 'destacado'];

    estudiantes.value.forEach(est => {
        if (!est.respuestas) est.respuestas = {};
        est.puntajes = est.puntajes || {};

        nivelesKeys.forEach(nivelKey => {
            const nivelConfig = niveles[nivelKey];
            if (nivelConfig) {
                const preguntas = nivelConfig.preguntas;
                const respuestas = est.respuestas[nivelKey] || [];

                let correctas = 0;
                preguntas.forEach((pregunta, idx) => {
                    if (respuestas[idx] && respuestas[idx] === pregunta.clave) {
                        correctas++;
                    }
                });

                // Ensure puntajes object exists
                if (est.puntajes) {
                    est.puntajes[nivelKey] = {
                        correctas,
                        total: preguntas.length,
                        porcentaje: preguntas.length > 0 ? (correctas / preguntas.length * 100) : 0
                    };
                }
            }
        });

        est.nivelFinal = determinarNivelFinal(est);
    });

    // Switch to results tab? User logic did this.
    // activeTab.value = 'resultados'; 
    // We can just show a toast or notification.
    updateChart();
};

const determinarNivelFinal = (est: Estudiante) => {
    const nivelesOrden = ['destacado', 'satisfactorio', 'proceso', 'inicio', 'pre-inicio'];
    const nombres = {
        'destacado': 'LOGRO DESTACADO',
        'satisfactorio': 'SATISFACTORIO',
        'proceso': 'EN PROCESO',
        'inicio': 'INICIO',
        'pre-inicio': 'PRE INICIO'
    };

    for (const nivelKey of nivelesOrden) {
        // Safe access
        if (est.puntajes && est.puntajes[nivelKey]) {
            const puntaje = est.puntajes[nivelKey];
            const nivelConfig = niveles[nivelKey];

            if (nivelConfig && nivelConfig.preguntas.length > 0 && puntaje.correctas > 0) {
                // Rule: >= 60% correct to achieve level (as per user code)
                if (puntaje.porcentaje >= 60) {
                    return nombres[nivelKey as keyof typeof nombres];
                }
            }
        }
    }
    return nombres['pre-inicio'];
};

const updateChart = () => {
    if (!chartContainer.value) return;

    // Clear previous chart
    d3.select(chartContainer.value).selectAll('*').remove();

    const total = stats.value.total;

    const data = [
        { label: 'Pre Inicio', value: stats.value['pre-inicio'], color: '#ef4444' },
        { label: 'Inicio', value: stats.value['inicio'], color: '#f97316' },
        { label: 'Proceso', value: stats.value['proceso'], color: '#eab308' },
        { label: 'Satisfactorio', value: stats.value['satisfactorio'], color: '#22c55e' },
        { label: 'Destacado', value: stats.value['destacado'], color: '#6366f1' }
    ].map(d => ({
        ...d,
        percentage: total > 0 ? Math.round((d.value / total) * 100) : 0
    }));

    const margin = { top: 20, right: 20, bottom: 40, left: 50 };
    const width = 350 - margin.left - margin.right;
    const height = 250 - margin.top - margin.bottom;

    const svg = d3.select(chartContainer.value)
        .append('svg')
        .attr('width', '100%')
        .attr('height', '100%')
        .attr('viewBox', `0 0 ${width + margin.left + margin.right} ${height + margin.top + margin.bottom}`)
        .append('g')
        .attr('transform', `translate(${margin.left},${margin.top})`);

    // X Scale
    const x = d3.scaleBand()
        .range([0, width])
        .domain(data.map(d => d.label))
        .padding(0.3);

    // Y Scale (0-100%)
    const y = d3.scaleLinear()
        .domain([0, 100])
        .range([height, 0]);

    // X Axis
    svg.append('g')
        .attr('transform', `translate(0,${height})`)
        .call(d3.axisBottom(x))
        .selectAll('text')
        .attr('transform', 'rotate(-25)')
        .style('text-anchor', 'end')
        .style('font-size', '10px')
        .style('fill', '#64748b');

    // Y Axis with percentage format
    svg.append('g')
        .call(d3.axisLeft(y).ticks(5).tickFormat(d => `${d}%`))
        .selectAll('text')
        .style('font-size', '10px')
        .style('fill', '#64748b');

    // Bars
    svg.selectAll('rect')
        .data(data)
        .enter()
        .append('rect')
        .attr('x', d => x(d.label) || 0)
        .attr('y', height)
        .attr('width', x.bandwidth())
        .attr('height', 0)
        .attr('fill', d => d.color)
        .attr('rx', 4)
        .style('opacity', 0.85)
        .style('cursor', 'pointer')
        .transition()
        .duration(800)
        .delay((_, i) => i * 100)
        .attr('y', d => y(d.percentage))
        .attr('height', d => height - y(d.percentage));

    // Percentage labels on top of bars
    svg.selectAll('.bar-label')
        .data(data)
        .enter()
        .append('text')
        .attr('class', 'bar-label')
        .attr('x', d => (x(d.label) || 0) + x.bandwidth() / 2)
        .attr('y', d => y(d.percentage) - 5)
        .attr('text-anchor', 'middle')
        .style('font-size', '12px')
        .style('font-weight', 'bold')
        .style('fill', '#334155')
        .style('opacity', 0)
        .text(d => `${d.percentage}%`)
        .transition()
        .duration(800)
        .delay((_, i) => i * 100 + 400)
        .style('opacity', 1);

    // Hover effects
    svg.selectAll('rect')
        .on('mouseover', function () {
            d3.select(this)
                .transition()
                .duration(200)
                .style('opacity', 1)
                .attr('transform', 'scale(1.02)');
        })
        .on('mouseout', function () {
            d3.select(this)
                .transition()
                .duration(200)
                .style('opacity', 0.85)
                .attr('transform', 'scale(1)');
        });
};

const exportarExcel = () => {
    if (estudiantes.value.length === 0) return;

    // Build CSV header
    let csv = 'N°,Nombre,';
    const nivelesKeys = ['pre-inicio', 'inicio', 'proceso', 'satisfactorio', 'destacado'];

    nivelesKeys.forEach(nivelKey => {
        const nivel = niveles[nivelKey];
        if (nivel) {
            const preguntas = nivel.preguntas;
            for (let i = 0; i < preguntas.length; i++) {
                csv += `${nivel.nombre} P${i + 1},`;
            }
        }
    });

    csv += 'Pre Inicio,Inicio,En Proceso,Satisfactorio,Destacado,Nivel Final\n';

    // Build rows
    estudiantes.value.forEach((est, index) => {
        csv += `${index + 1},"${est.nombre || ''}",`;

        nivelesKeys.forEach(nivelKey => {
            const respuestas = est.respuestas[nivelKey] || [];
            const nivel = niveles[nivelKey];
            if (nivel) {
                const preguntas = nivel.preguntas;
                for (let i = 0; i < preguntas.length; i++) {
                    csv += `${respuestas[i] || ''},`;
                }
            }
        });

        const puntajes = est.puntajes || {};
        nivelesKeys.forEach(nivelKey => {
            csv += `${puntajes[nivelKey]?.correctas || 0}/${puntajes[nivelKey]?.total || 0},`;
        });

        csv += `"${est.nivelFinal || 'Sin calcular'}"\n`;
    });

    // Download
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = `sistematizador_resultados_${new Date().toISOString().split('T')[0]}.csv`;
    link.click();

    // Cleanup
    URL.revokeObjectURL(link.href);
};

// Lifecycle
onMounted(() => {
    loadGrados();
    // Load from local storage if exists? The user code did this.
    const saved = localStorage.getItem('lectoSistemData');
    if (saved) {
        try {
            const data = JSON.parse(saved);
            if (data.competencia) competencia.value = data.competencia;
            if (data.estudiantes) estudiantes.value = data.estudiantes;
            // careful merging observable query configs if we want to support DB loaded ones
            // For now, let's respect the reactive state initialization
        } catch (e) {
            console.error("Local Storage Error", e);
        }
    }
});

// Watch tab to update chart
watch(activeTab, (newTab) => {
    if (newTab === 'resultados') {
        setTimeout(() => updateChart(), 100);
    }
});


</script>

<template>
    <div class="lectosistem-theme">
        <!-- Header Nav within Component -->
        <div class="flex gap-2 mb-6 p-2 bg-slate-800/5 dark:bg-slate-700/50 rounded-xl w-fit">
            <button @click="activeTab = 'config'"
                class="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all"
                :class="activeTab === 'config' ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-500/30' : 'text-slate-600 dark:text-slate-400 hover:bg-white/50 dark:hover:bg-slate-700'">
                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none"
                    stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <path
                        d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" />
                    <circle cx="12" cy="12" r="3" />
                </svg>
                Configuración
            </button>
            <button @click="activeTab = 'registro'"
                class="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all"
                :class="activeTab === 'registro' ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-500/30' : 'text-slate-600 dark:text-slate-400 hover:bg-white/50 dark:hover:bg-slate-700'">
                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none"
                    stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2" />
                    <rect x="8" y="2" width="8" height="4" rx="1" ry="1" />
                    <path d="M9 14l2 2 4-4" />
                </svg>
                Registro
            </button>
            <button @click="activeTab = 'resultados'"
                class="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all"
                :class="activeTab === 'resultados' ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-500/30' : 'text-slate-600 dark:text-slate-400 hover:bg-white/50 dark:hover:bg-slate-700'">
                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none"
                    stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M3 3v18h18" />
                    <path d="M18.7 8l-5.1 5.2-2.8-2.7L7 14.3" />
                </svg>
                Resultados
            </button>
        </div>

        <!-- Active Content -->
        <div class="tab-content transition-all duration-300">

            <!-- Tab 1: Config -->
            <div v-show="activeTab === 'config'" class="animate-fadeIn">
                <div class="flex flex-wrap justify-between items-start mb-8 gap-4">
                    <div>
                        <h2
                            class="text-2xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-indigo-600 to-purple-600 dark:from-indigo-400 dark:to-purple-400">
                            Configuración de Desempeños</h2>
                        <p class="text-slate-500 dark:text-slate-400">Define la competencia y los desempeños a evaluar
                            por cada nivel</p>
                    </div>
                    <!-- Grade Selector -->
                    <div class="w-full md:w-64">
                        <ComboBox v-model="selectedGradoId" :options="gradoOptions"
                            placeholder="Seleccionar Grado para cargar desempeños..." />
                    </div>
                </div>

                <!-- Competencia Card -->
                <div class="config-card mb-8">
                    <div class="card-header flex items-center gap-4 mb-4">
                        <div
                            class="w-12 h-12 rounded-xl bg-indigo-100 dark:bg-indigo-900/30 text-indigo-600 dark:text-indigo-400 flex items-center justify-center">
                            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"
                                fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"
                                stroke-linejoin="round">
                                <path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z" />
                                <path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z" />
                            </svg>
                        </div>
                        <div>
                            <h3 class="text-lg font-semibold text-slate-800 dark:text-white">Competencia a Evaluar</h3>
                            <p class="text-sm text-slate-500">Ingrese la competencia del área curricular</p>
                        </div>
                    </div>
                    <input v-model="competencia" type="text"
                        class="input-competencia w-full p-4 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-700 rounded-xl focus:ring-2 focus:ring-indigo-500 outline-none transition-all" />
                </div>

                <!-- Niveles Container -->
                <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
                    <div v-for="(nivel, key) in niveles" :key="key"
                        class="nivel-card rounded-xl border transition-all hover:shadow-lg bg-white dark:bg-slate-800"
                        :style="{ borderTop: `4px solid ${nivel.color}` }">
                        <div class="p-6">
                            <div class="flex items-center gap-2 mb-4 flex-wrap">
                                <span class="px-3 py-1 rounded-md text-xs font-bold tracking-wider uppercase"
                                    :style="{ backgroundColor: nivel.bg, color: nivel.color }">
                                    {{ nivel.nombre }}
                                </span>
                                <span class="text-xs text-slate-500">{{ nivel.descripcion }}</span>
                            </div>

                            <div class="space-y-3 mb-4">
                                <div v-for="(pregunta, idx) in nivel.preguntas" :key="idx"
                                    class="group relative bg-slate-50 dark:bg-slate-900 p-3 rounded-lg border border-slate-100 dark:border-slate-700">
                                    <span
                                        class="absolute -left-2 -top-2 flex items-center justify-center w-6 h-6 rounded-full bg-indigo-600 text-white text-xs font-bold shadow-md ring-2 ring-white dark:ring-slate-800">
                                        {{ idx + 1 }}
                                    </span>

                                    <div class="mb-2 pl-2">
                                        <!-- Use ComboBox to select Desempeño from DB -->
                                        <ComboBox :model-value="pregunta.desempenoId"
                                            @update:model-value="(val) => onDesempenoSelect(String(key), idx, val)"
                                            :options="desempenoOptions" placeholder="Seleccionar Desempeño..." />
                                    </div>

                                    <!-- Fallback or Full Text Edit -->
                                    <textarea v-model="pregunta.descripcion" placeholder="Descripción del desempeño..."
                                        rows="2"
                                        class="w-full text-sm p-2 bg-transparent border-none focus:ring-0 text-slate-700 dark:text-slate-300 resize-none"></textarea>

                                    <div
                                        class="flex items-center justify-between mt-2 pt-2 border-t border-slate-200 dark:border-slate-700">
                                        <select v-model="pregunta.clave"
                                            class="text-sm bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-600 rounded px-2 py-1">
                                            <option value="">Clave</option>
                                            <option value="A">A</option>
                                            <option value="B">B</option>
                                            <option value="C">C</option>
                                            <option value="D">D</option>
                                        </select>

                                        <button @click="removePregunta(String(key), idx)"
                                            class="text-red-400 hover:text-red-600 p-1 rounded hover:bg-red-50 dark:hover:bg-red-900/20">
                                            <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14"
                                                viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                                                stroke-linecap="round" stroke-linejoin="round">
                                                <line x1="18" y1="6" x2="6" y2="18" />
                                                <line x1="6" y1="6" x2="18" y2="18" />
                                            </svg>
                                        </button>
                                    </div>
                                </div>
                            </div>

                            <button @click="addPregunta(String(key))"
                                class="w-full py-3 border-2 border-dashed border-slate-200 dark:border-slate-700 rounded-lg text-slate-500 hover:text-indigo-600 hover:border-indigo-300 hover:bg-indigo-50 dark:hover:bg-indigo-900/10 transition-colors flex items-center justify-center gap-2 text-sm font-medium">
                                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24"
                                    fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"
                                    stroke-linejoin="round">
                                    <line x1="12" y1="5" x2="12" y2="19" />
                                    <line x1="5" y1="12" x2="19" y2="12" />
                                </svg>
                                Agregar Pregunta
                            </button>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Tab 2: Registro -->
            <div v-show="activeTab === 'registro'" class="animate-fadeIn">
                <div class="flex justify-between items-center mb-6">
                    <div>
                        <h2
                            class="text-2xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-indigo-600 to-purple-600">
                            Registro de Estudiantes</h2>
                        <p class="text-slate-500">Ingresa los datos y respuestas</p>
                    </div>
                    <div class="flex gap-2">
                        <button @click="addEstudiante"
                            class="px-4 py-2 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700 font-medium flex items-center gap-2">
                            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24"
                                fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"
                                stroke-linejoin="round">
                                <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
                                <circle cx="9" cy="7" r="4" />
                                <line x1="19" y1="8" x2="19" y2="14" />
                                <line x1="22" y1="11" x2="16" y2="11" />
                            </svg>
                            Agregar
                        </button>
                        <button @click="calcularResultados"
                            class="px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 font-medium shadow-lg shadow-indigo-500/30 flex items-center gap-2">
                            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24"
                                fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"
                                stroke-linejoin="round">
                                <rect x="4" y="2" width="16" height="20" rx="2" />
                                <line x1="8" y1="6" x2="16" y2="6" />
                                <line x1="8" y1="10" x2="16" y2="10" />
                                <line x1="8" y1="14" x2="12" y2="14" />
                                <line x1="8" y1="18" x2="10" y2="18" />
                            </svg>
                            Calcular
                        </button>
                    </div>
                </div>

                <div
                    class="overflow-x-auto rounded-xl border border-slate-200 dark:border-slate-700 shadow-sm bg-white dark:bg-slate-800">
                    <table class="w-full text-sm">
                        <thead>
                            <tr>
                                <th rowspan="2"
                                    class="p-3 bg-slate-50 dark:bg-slate-900 border-b border-r border-slate-200 dark:border-slate-700 text-left font-semibold text-slate-600 dark:text-slate-300 w-12">
                                    #</th>
                                <th rowspan="2"
                                    class="p-3 bg-slate-50 dark:bg-slate-900 border-b border-r border-slate-200 dark:border-slate-700 text-left font-semibold text-slate-600 dark:text-slate-300 min-w-[200px]">
                                    Apellidos y Nombres</th>

                                <template v-for="(nivel, key) in niveles" :key="key">
                                    <th v-if="nivel.preguntas.length" :colspan="nivel.preguntas.length"
                                        class="p-2 border-b border-r border-slate-200 dark:border-slate-700 text-center font-bold text-xs uppercase tracking-wider"
                                        :style="{ backgroundColor: nivel.bg, color: nivel.color }">
                                        {{ nivel.nombre }}
                                    </th>
                                </template>

                                <th rowspan="2"
                                    class="p-3 bg-slate-50 dark:bg-slate-900 border-b text-center font-semibold text-slate-600 dark:text-slate-300 min-w-[120px]">
                                    Nivel Final</th>
                                <th rowspan="2" class="p-3 bg-slate-50 dark:bg-slate-900 border-b text-center w-12">
                                </th>
                            </tr>
                            <tr>
                                <template v-for="(nivel, key) in niveles" :key="key + '-sub'">
                                    <th v-for="(preg, idx) in nivel.preguntas" :key="idx"
                                        class="p-2 border-b border-r border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-900 text-xs text-center text-slate-500"
                                        :title="preg.descripcion">
                                        <div class="flex flex-col items-center">
                                            <span>P{{ idx + 1 }}</span>
                                            <span v-if="preg.clave" class="text-[10px] font-bold px-1 rounded mt-0.5"
                                                :style="{ backgroundColor: nivel.bg, color: nivel.color }">
                                                {{ preg.clave }}
                                            </span>
                                        </div>
                                    </th>
                                </template>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-slate-100 dark:divide-slate-700">
                            <tr v-for="(est, i) in estudiantes" :key="i"
                                class="hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors">
                                <td
                                    class="p-3 border-r border-slate-100 dark:border-slate-700 text-center text-slate-500">
                                    {{ i + 1 }}</td>
                                <td class="p-3 border-r border-slate-100 dark:border-slate-700">
                                    <input v-model="est.nombre" type="text" placeholder="Nombre del estudiante"
                                        class="w-full bg-transparent outline-none text-slate-700 dark:text-slate-200" />
                                </td>

                                <template v-for="(nivel, key) in niveles" :key="key">
                                    <td v-for="(_pregunta, idx) in nivel.preguntas" :key="idx"
                                        class="p-1 border-r border-slate-100 dark:border-slate-700 text-center">
                                        <select :value="est.respuestas[String(key)]?.[idx] || ''" @change="(e) => {
                                            if (!est.respuestas[String(key)]) est.respuestas[String(key)] = [];
                                            const respArray = est.respuestas[String(key)];
                                            if (respArray) respArray[idx] = (e.target as HTMLSelectElement).value;
                                        }"
                                            class="w-full text-center bg-transparent outline-none cursor-pointer focus:bg-indigo-50 dark:focus:bg-indigo-900/20 rounded py-1">
                                            <option value="">-</option>
                                            <option value="A">A</option>
                                            <option value="B">B</option>
                                            <option value="C">C</option>
                                            <option value="D">D</option>
                                        </select>
                                    </td>
                                </template>

                                <td class="p-3 text-center">
                                    <span v-if="est.nivelFinal" class="px-2 py-1 rounded text-xs font-bold" :class="{
                                        'bg-red-100 text-red-600': est.nivelFinal === 'PRE INICIO',
                                        'bg-orange-100 text-orange-600': est.nivelFinal === 'INICIO',
                                        'bg-yellow-100 text-yellow-600': est.nivelFinal === 'EN PROCESO',
                                        'bg-green-100 text-green-600': est.nivelFinal === 'SATISFACTORIO',
                                        'bg-indigo-100 text-indigo-600': est.nivelFinal === 'LOGRO DESTACADO',
                                    }">
                                        {{ est.nivelFinal }}
                                    </span>
                                    <span v-else class="text-slate-400 text-xs">-</span>
                                </td>

                                <td class="p-3 text-center">
                                    <button @click="removeEstudiante(i)"
                                        class="text-slate-400 hover:text-red-500 transition-colors">
                                        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"
                                            viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                                            stroke-linecap="round" stroke-linejoin="round">
                                            <polyline points="3 6 5 6 21 6" />
                                            <path
                                                d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
                                        </svg>
                                    </button>
                                </td>
                            </tr>
                            <tr v-if="estudiantes.length === 0">
                                <td :colspan="20" class="p-12 text-center text-slate-500">
                                    <div class="flex flex-col items-center gap-3">
                                        <div
                                            class="w-16 h-16 bg-slate-100 dark:bg-slate-800 rounded-full flex items-center justify-center text-slate-400">
                                            <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"
                                                viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                                                stroke-linecap="round" stroke-linejoin="round">
                                                <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
                                                <circle cx="9" cy="7" r="4" />
                                                <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
                                                <path d="M16 3.13a4 4 0 0 1 0 7.75" />
                                            </svg>
                                        </div>
                                        <p class="font-medium">No hay estudiantes registrados</p>
                                        <p class="text-sm">Agrega estudiantes para comenzar la evaluación</p>
                                    </div>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>

            <!-- Tab 3: Resultados -->
            <div v-show="activeTab === 'resultados'" class="animate-fadeIn">
                <div class="flex justify-between items-center mb-8">
                    <div>
                        <h2
                            class="text-2xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-indigo-600 to-purple-600">
                            Resultados del Análisis</h2>
                        <p class="text-slate-500">Resumen estadístico y gráficos</p>
                    </div>
                    <button @click="exportarExcel"
                        class="px-4 py-2 bg-emerald-600 text-white rounded-lg hover:bg-emerald-700 font-medium shadow-lg shadow-emerald-500/30 flex items-center gap-2">
                        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none"
                            stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                            <polyline points="7,10 12,15 17,10" />
                            <line x1="12" y1="15" x2="12" y2="3" />
                        </svg>
                        Exportar Excel
                    </button>
                </div>

                <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4 mb-8">
                    <!-- Stat Cards -->
                    <div
                        class="bg-white dark:bg-slate-800 p-4 rounded-xl border border-slate-200 dark:border-slate-700 shadow-sm relative overflow-hidden group">
                        <div class="absolute top-0 left-0 w-full h-1 bg-indigo-500"></div>
                        <p class="text-xs text-slate-500 font-bold uppercase tracking-wider mb-1">Total</p>
                        <p class="text-2xl font-bold text-slate-800 dark:text-white">{{ stats.total }}</p>
                    </div>

                    <div v-for="(count, key) in { 'Pre Inicio': stats['pre-inicio'], 'Inicio': stats['inicio'], 'Proceso': stats['proceso'], 'Satisfactorio': stats['satisfactorio'], 'Destacado': stats['destacado'] }"
                        :key="key"
                        class="bg-white dark:bg-slate-800 p-4 rounded-xl border border-slate-200 dark:border-slate-700 shadow-sm relative overflow-hidden">
                        <div class="absolute top-0 left-0 w-full h-1" :class="{
                            'bg-red-500': key === 'Pre Inicio',
                            'bg-orange-500': key === 'Inicio',
                            'bg-yellow-500': key === 'Proceso',
                            'bg-green-500': key === 'Satisfactorio',
                            'bg-indigo-500': key === 'Destacado'
                        }"></div>
                        <p class="text-xs text-slate-500 font-bold uppercase tracking-wider mb-1">{{ key }}</p>
                        <div class="flex items-end justify-between">
                            <p class="text-2xl font-bold text-slate-800 dark:text-white">{{ count }}</p>
                            <span
                                class="text-xs font-medium px-1.5 py-0.5 rounded bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-400">
                                {{ stats.total > 0 ? Math.round(count / stats.total * 100) : 0 }}%
                            </span>
                        </div>
                    </div>
                </div>

                <div class="grid lg:grid-cols-2 gap-6">
                    <!-- Chart -->
                    <div
                        class="bg-white dark:bg-slate-800 p-6 rounded-xl border border-slate-200 dark:border-slate-700 shadow-sm">
                        <h3 class="font-bold text-slate-700 dark:text-slate-200 mb-6">Distribución por Niveles</h3>
                        <div class="relative h-64 w-full flex items-center justify-center">
                            <div ref="chartContainer" class="w-full h-full flex items-center justify-center"></div>
                        </div>

                        <!-- Summary Table -->
                        <div class="mt-6 border-t border-slate-200 dark:border-slate-700 pt-4">
                            <h4 class="text-sm font-semibold text-slate-600 dark:text-slate-400 mb-3">Resumen de Niveles
                            </h4>
                            <div class="overflow-x-auto">
                                <table class="w-full text-sm">
                                    <thead>
                                        <tr class="border-b border-slate-200 dark:border-slate-700">
                                            <th
                                                class="py-2 px-3 text-left font-semibold text-slate-600 dark:text-slate-400">
                                                Nivel
                                            </th>
                                            <th
                                                class="py-2 px-3 text-center font-semibold text-slate-600 dark:text-slate-400">
                                                Cantidad</th>
                                            <th
                                                class="py-2 px-3 text-center font-semibold text-slate-600 dark:text-slate-400">
                                                Porcentaje</th>
                                        </tr>
                                    </thead>
                                    <tbody class="divide-y divide-slate-100 dark:divide-slate-700">
                                        <tr>
                                            <td class="py-2 px-3 flex items-center gap-2">
                                                <span class="w-3 h-3 rounded-full bg-red-500"></span>
                                                <span class="text-slate-700 dark:text-slate-300">Pre Inicio</span>
                                            </td>
                                            <td
                                                class="py-2 px-3 text-center font-semibold text-slate-800 dark:text-white">
                                                {{
                                                    stats['pre-inicio'] }}</td>
                                            <td class="py-2 px-3 text-center">
                                                <span
                                                    class="px-2 py-0.5 rounded bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400 text-xs font-bold">
                                                    {{ stats.total > 0 ? Math.round(stats['pre-inicio'] / stats.total *
                                                        100) : 0 }}%
                                                </span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td class="py-2 px-3 flex items-center gap-2">
                                                <span class="w-3 h-3 rounded-full bg-orange-500"></span>
                                                <span class="text-slate-700 dark:text-slate-300">Inicio</span>
                                            </td>
                                            <td
                                                class="py-2 px-3 text-center font-semibold text-slate-800 dark:text-white">
                                                {{
                                                    stats['inicio'] }}</td>
                                            <td class="py-2 px-3 text-center">
                                                <span
                                                    class="px-2 py-0.5 rounded bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400 text-xs font-bold">
                                                    {{ stats.total > 0 ? Math.round(stats['inicio'] / stats.total * 100)
                                                        : 0 }}%
                                                </span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td class="py-2 px-3 flex items-center gap-2">
                                                <span class="w-3 h-3 rounded-full bg-yellow-500"></span>
                                                <span class="text-slate-700 dark:text-slate-300">En Proceso</span>
                                            </td>
                                            <td
                                                class="py-2 px-3 text-center font-semibold text-slate-800 dark:text-white">
                                                {{
                                                    stats['proceso'] }}</td>
                                            <td class="py-2 px-3 text-center">
                                                <span
                                                    class="px-2 py-0.5 rounded bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400 text-xs font-bold">
                                                    {{ stats.total > 0 ? Math.round(stats['proceso'] / stats.total *
                                                        100) : 0 }}%
                                                </span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td class="py-2 px-3 flex items-center gap-2">
                                                <span class="w-3 h-3 rounded-full bg-green-500"></span>
                                                <span class="text-slate-700 dark:text-slate-300">Satisfactorio</span>
                                            </td>
                                            <td
                                                class="py-2 px-3 text-center font-semibold text-slate-800 dark:text-white">
                                                {{
                                                    stats['satisfactorio'] }}</td>
                                            <td class="py-2 px-3 text-center">
                                                <span
                                                    class="px-2 py-0.5 rounded bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400 text-xs font-bold">
                                                    {{ stats.total > 0 ? Math.round(stats['satisfactorio'] / stats.total
                                                        * 100) : 0
                                                    }}%
                                                </span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td class="py-2 px-3 flex items-center gap-2">
                                                <span class="w-3 h-3 rounded-full bg-indigo-500"></span>
                                                <span class="text-slate-700 dark:text-slate-300">Logro Destacado</span>
                                            </td>
                                            <td
                                                class="py-2 px-3 text-center font-semibold text-slate-800 dark:text-white">
                                                {{
                                                    stats['destacado'] }}</td>
                                            <td class="py-2 px-3 text-center">
                                                <span
                                                    class="px-2 py-0.5 rounded bg-indigo-100 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-400 text-xs font-bold">
                                                    {{ stats.total > 0 ? Math.round(stats['destacado'] / stats.total *
                                                        100) : 0 }}%
                                                </span>
                                            </td>
                                        </tr>
                                    </tbody>
                                    <tfoot class="border-t-2 border-slate-300 dark:border-slate-600">
                                        <tr class="bg-slate-50 dark:bg-slate-900">
                                            <td class="py-2 px-3 font-bold text-slate-800 dark:text-white">Total</td>
                                            <td class="py-2 px-3 text-center font-bold text-slate-800 dark:text-white">
                                                {{
                                                    stats.total }}</td>
                                            <td class="py-2 px-3 text-center font-bold text-slate-800 dark:text-white">
                                                100%</td>
                                        </tr>
                                    </tfoot>
                                </table>
                            </div>
                        </div>
                    </div>

                    <!-- Resumen Table -->
                    <div
                        class="bg-white dark:bg-slate-800 p-6 rounded-xl border border-slate-200 dark:border-slate-700 shadow-sm flex flex-col">
                        <h3 class="font-bold text-slate-700 dark:text-slate-200 mb-6">Resumen por Estudiante</h3>
                        <div
                            class="overflow-y-auto flex-1 max-h-[300px] border rounded-lg border-slate-100 dark:border-slate-700">
                            <table class="w-full text-sm">
                                <thead class="bg-slate-50 dark:bg-slate-900 sticky top-0">
                                    <tr>
                                        <th class="p-2 text-left font-semibold text-slate-600 dark:text-slate-400">
                                            Estudiante</th>
                                        <th class="p-2 text-center font-semibold text-slate-600 dark:text-slate-400">
                                            Nivel</th>
                                    </tr>
                                </thead>
                                <tbody class="divide-y divide-slate-100 dark:divide-slate-700">
                                    <tr v-for="(est, i) in estudiantes" :key="i">
                                        <td class="p-2 text-slate-700 dark:text-slate-300">{{ est.nombre || 'Sin Nombre'
                                        }}</td>
                                        <td class="p-2 text-center">
                                            <span v-if="est.nivelFinal"
                                                class="px-2 py-0.5 rounded text-[10px] font-bold uppercase" :class="{
                                                    'bg-red-100 text-red-600': est.nivelFinal === 'PRE INICIO',
                                                    'bg-orange-100 text-orange-600': est.nivelFinal === 'INICIO',
                                                    'bg-yellow-100 text-yellow-600': est.nivelFinal === 'EN PROCESO',
                                                    'bg-green-100 text-green-600': est.nivelFinal === 'SATISFACTORIO',
                                                    'bg-indigo-100 text-indigo-600': est.nivelFinal === 'LOGRO DESTACADO',
                                                }">
                                                {{ est.nivelFinal }}
                                            </span>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>

        </div>
    </div>
</template>

<style scoped>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap');

/* Add some custom animations */
@keyframes fadeIn {
    from {
        opacity: 0;
        transform: translateY(10px);
    }

    to {
        opacity: 1;
        transform: translateY(0);
    }
}

.animate-fadeIn {
    animation: fadeIn 0.3s ease-out forwards;
}

/* Ensure Chart.js canvas has size */
canvas {
    max-width: 100%;
}
</style>
