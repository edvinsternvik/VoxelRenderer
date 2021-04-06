#section vertex
#version 430 core
layout (location = 0) in vec3 aPos;

out vec2 fragPos;

void main() {
   fragPos = vec2((aPos.x + 1.0) / 2.0, (aPos.y + 1.0) / 2.0);
   gl_Position = vec4(aPos.x, aPos.y, aPos.z, 1.0);
}


#section fragment
#version 430 core

const double deltaRayOffset = 0.000000001;

struct OctreeNode {
    uint parentIndex;
    uint childrenIndices[8];
    int isSolidColor;
    uint dataIndex;
};

layout(std430, binding = 0) buffer OctreeSSBO {
   OctreeNode octreeNodes[];
};

layout(std430, binding = 1) buffer ChunkDataSSBO {
   uint chunkData[];
};

uniform vec3 u_cameraPos;
uniform float u_cameraDir;
uniform uint u_worldWidth;
uniform uint u_maxOctreeDepth;
uniform uint u_chunkWidth;

out vec4 FragColor;
in vec2 fragPos;

uint getVoxelByte(uint chunkDataIndex, ivec3 iLocalPos) {
   uint localVoxelID = iLocalPos.x + iLocalPos.y * u_chunkWidth + iLocalPos.z * u_chunkWidth * u_chunkWidth;
   uint voxelID = chunkDataIndex + localVoxelID;

   // Each voxel is one byte but we index it as a uint, so the voxelID is divided by 4 and the appropriate byte is returned.
   uint voxelIndex = voxelID >> 2;
   uint voxelDataWord = chunkData[voxelIndex];
   return (voxelDataWord >> ((voxelID % 4) << 3)) & uint(0x000000FF);
}

double getDeltaRay(dvec3 pos, ivec3 ipos, double cubeWidth, dvec3 rayDir, dvec3 invRayDir) {
   dvec3 dPos;
   if(sign(rayDir.x) == 1) dPos.x = cubeWidth + ipos.x - pos.x;
   else if(pos.x == ipos.x) dPos.x = -cubeWidth;
   else dPos.x = ipos.x - pos.x;

   if(sign(rayDir.y) == 1) dPos.y = cubeWidth + ipos.y - pos.y;
   else if(pos.y == ipos.y) dPos.y = -cubeWidth;
   else dPos.y = ipos.y - pos.y;
   
   if(sign(rayDir.z) == 1) dPos.z = cubeWidth + ipos.z - pos.z;
   else if(pos.z == ipos.z) dPos.z = -cubeWidth;
   else dPos.z = ipos.z - pos.z;

   dvec3 dRay = dPos * invRayDir;

   return min(dRay.x, min(dRay.y, dRay.z));
}

void getOctreeNode(inout uint currentOctreeNodeID, inout uint depth, inout dvec3 pos) {
   while(octreeNodes[currentOctreeNodeID].isSolidColor == 0 && depth < u_maxOctreeDepth) {
      int childIndex = 0;
      if(pos.x < 0 && pos.y < 0 && pos.z < 0) childIndex = 0;
      else if(pos.x >= 0 && pos.y <  0 && pos.z <  0) childIndex = 1;
      else if(pos.x <  0 && pos.y >= 0 && pos.z <  0) childIndex = 2;
      else if(pos.x >= 0 && pos.y >= 0 && pos.z <  0) childIndex = 3;

      else if(pos.x <  0 && pos.y <  0 && pos.z >= 0) childIndex = 4;
      else if(pos.x >= 0 && pos.y <  0 && pos.z >= 0) childIndex = 5;
      else if(pos.x <  0 && pos.y >= 0 && pos.z >= 0) childIndex = 6;
      else if(pos.x >= 0 && pos.y >= 0 && pos.z >= 0) childIndex = 7;

      double qWidth = u_worldWidth / pow(2, depth + 2);
      pos.x += qWidth * ((pos.x >= 0) ? -1.0 : 1.0);
      pos.y += qWidth * ((pos.y >= 0) ? -1.0 : 1.0);
      pos.z += qWidth * ((pos.z >= 0) ? -1.0 : 1.0);

      depth++;
      currentOctreeNodeID = octreeNodes[currentOctreeNodeID].childrenIndices[childIndex];
   }
}

uint getVoxelData(uint chunkDataIndex, dvec3 localPos, dvec3 rayDir, dvec3 invRayDir) {
   int iteration;
   for(iteration = 0; iteration < 100; ++iteration) {
      ivec3 iLocalPos = ivec3(floor(localPos.x), floor(localPos.y), floor(localPos.z));
      if(iLocalPos.x < 0 || iLocalPos.x >= u_chunkWidth || iLocalPos.y < 0.0 || iLocalPos.y >= u_chunkWidth || iLocalPos.z < 0.0 || iLocalPos.z >= u_chunkWidth) {
         break;
      }

      uint voxelByte = getVoxelByte(chunkDataIndex, iLocalPos);
      if(voxelByte != 0) return voxelByte;

      double deltaRay = getDeltaRay(localPos, iLocalPos, 1.0, rayDir, invRayDir);
      localPos += rayDir * (deltaRay + deltaRayOffset);
   }

   return 0;
}

vec3 getPixelColor(dvec3 pos, dvec3 rayDir, uint maxIterations) {
   double dist = 0.0;

   dvec3 invRayDir = 1.0 / rayDir;
   uint d = 0;
   double hWorldWidth = u_worldWidth / 2.0;

   int iteration;
   for(iteration = 0; iteration < maxIterations; ++iteration) {
      if(pos.x <= -hWorldWidth || pos.x >= hWorldWidth || pos.y <= -hWorldWidth || pos.y >= hWorldWidth || pos.z <= -hWorldWidth || pos.z >= hWorldWidth) {
         break;
      }

      uint currentOctreeNodeID = 0;
      uint currentDepth = 0;
      dvec3 localPos = pos;
      getOctreeNode(currentOctreeNodeID, currentDepth, localPos);

      d = max(currentDepth, d);
      if(currentDepth == u_maxOctreeDepth) {
         if(octreeNodes[currentOctreeNodeID].isSolidColor == 0) {
            dvec3 localChunkPos = localPos + dvec3(u_chunkWidth, u_chunkWidth, u_chunkWidth) / 2;
            uint voxelData = getVoxelData(octreeNodes[currentOctreeNodeID].dataIndex, localChunkPos, rayDir, invRayDir);
            if(voxelData != 0) {
               break;
            }
         }
         else if(octreeNodes[currentOctreeNodeID].dataIndex != 0) {
            return vec3(1.0, 1.0, 0.0);
         }
      }

      double width = u_worldWidth / pow(2, currentDepth);
      ivec3 ipos = ivec3(floor(pos.x / width) * width, floor(pos.y / width) * width, floor(pos.z / width) * width);
      double deltaRay = getDeltaRay(pos, ipos, width, rayDir, invRayDir);
      pos += rayDir * (deltaRay + deltaRayOffset);

      dist += deltaRay;

   }

   double a = double(iteration) / 20.0;
   return vec3(a,a,a);
}

void main() {
   dvec3 pos = dvec3(u_cameraPos);

   float angleY = (fragPos.x - 0.5) * 3.1415926535 * 0.5 + u_cameraDir;
   float angleX = (fragPos.y - 0.5) * 3.1415926535 * 0.5;
   dvec3 rayDir = dvec3(sin(angleY), angleX, cos(angleY));
   rayDir = normalize(rayDir);

   FragColor = vec4(getPixelColor(pos, rayDir, 100), 1.0);
}