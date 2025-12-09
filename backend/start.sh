#!/bin/bash
set -e

# Navegar al directorio donde está este script (si es necesario) o asumir que se corre desde root backend
# Render ejecuta el comando desde el "Root Directory" configurado. Supongamos que Root Dir es 'backend' o la raíz del repo.
# Si el root dir es 'backend', estamos bien.

echo "🔄 Iniciando script de arranque para Render..."

# 1. Ejecutar la carga de datos (Se va a recrear la BD desempeños.db)
echo "📊 Cargando base de datos de desempeños desde Excel..."
python -m scripts.load_desempenos

# 2. Iniciar la aplicación Uvicorn
# Usamos la variable de entorno PORT que provee Render, por defecto 10000
echo "🚀 Iniciando servidor Uvicorn en el puerto ${PORT:-10000}..."
exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-10000}
