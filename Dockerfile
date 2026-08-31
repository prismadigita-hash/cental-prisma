# Central Prisma — site estático servido por nginx
# EasyPanel detecta este Dockerfile e faz o deploy automaticamente.
FROM nginx:alpine

# Copia os arquivos do site para a pasta pública do nginx
COPY . /usr/share/nginx/html

# nginx já serve index.html na raiz por padrão
EXPOSE 80
