<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import * as echarts from 'echarts/core'
import { LineChart } from 'echarts/charts'
import { GridComponent, TooltipComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'

interface MetricPoint {
  timestamp: string
  value: number
}

echarts.use([LineChart, GridComponent, TooltipComponent, CanvasRenderer])

const props = defineProps<{
  title: string
  data: MetricPoint[]
  unit?: string
  color?: string
}>()

const chartRef = ref<HTMLDivElement | null>(null)
let chart: echarts.ECharts | null = null

function render() {
  if (!chartRef.value) return
  if (!chart) chart = echarts.init(chartRef.value, undefined, { renderer: 'canvas' })

  chart.setOption({
    backgroundColor: 'transparent',
    grid: { left: 40, right: 16, top: 24, bottom: 28 },
    tooltip: {
      trigger: 'axis',
      backgroundColor: '#161d26',
      borderColor: '#252f3d',
      textStyle: { color: '#c8d0dc', fontSize: 12 },
    },
    xAxis: {
      type: 'category',
      data: props.data.map((p) => p.timestamp),
      axisLine: { lineStyle: { color: '#252f3d' } },
      axisLabel: { color: '#6b7a8f', fontSize: 10 },
    },
    yAxis: {
      type: 'value',
      axisLine: { show: false },
      splitLine: { lineStyle: { color: '#252f3d', type: 'dashed' } },
      axisLabel: { color: '#6b7a8f', fontSize: 10 },
    },
    series: [
      {
        type: 'line',
        data: props.data.map((p) => p.value),
        smooth: true,
        symbol: 'none',
        lineStyle: { color: props.color ?? '#e8a838', width: 2 },
        areaStyle: {
          color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
            { offset: 0, color: `${props.color ?? '#e8a838'}40` },
            { offset: 1, color: `${props.color ?? '#e8a838'}05` },
          ]),
        },
      },
    ],
  })
}

function handleResize() {
  chart?.resize()
}

watch(() => props.data, render, { deep: true })

onMounted(() => {
  render()
  window.addEventListener('resize', handleResize)
})

onBeforeUnmount(() => {
  window.removeEventListener('resize', handleResize)
  chart?.dispose()
})
</script>

<template>
  <div class="border border-panel-border bg-panel-surface">
    <div class="border-b border-panel-border px-4 py-2 text-xs uppercase tracking-wide text-panel-muted">
      {{ title }}
      <span v-if="unit" class="ml-1 normal-case">({{ unit }})</span>
    </div>
    <div ref="chartRef" class="h-48 w-full" />
  </div>
</template>
