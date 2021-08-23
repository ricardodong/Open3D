// ----------------------------------------------------------------------------
// -                        Open3D: www.open3d.org                            -
// ----------------------------------------------------------------------------
// The MIT License (MIT)
//
// Copyright (c) 2018-2021 www.open3d.org
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.
// ----------------------------------------------------------------------------

#include "open3d/t/pipelines/registration/Registration.h"

#include <benchmark/benchmark.h>

#include "open3d/core/CUDAUtils.h"
#include "open3d/core/nns/NearestNeighborSearch.h"
#include "open3d/t/io/PointCloudIO.h"
#include "open3d/t/pipelines/registration/TransformationEstimation.h"

// Testing parameters:
// Filename for pointcloud registration data.
static const std::string source_pointcloud_filename =
        std::string(TEST_DATA_DIR) + "/ICP/cloud_bin_0.pcd";
static const std::string target_pointcloud_filename =
        std::string(TEST_DATA_DIR) + "/ICP/cloud_bin_1.pcd";

static const double voxel_downsampling_factor = 0.02;

// ICP ConvergenceCriteria.
static const double relative_fitness = 1e-6;
static const double relative_rmse = 1e-6;
static const int max_iterations = 30;

// NNS parameter.
static const double max_correspondence_distance = 0.05;

// Initial transformation guess for registation.
static const std::vector<float> initial_transform_flat{
        0.862, 0.011, -0.507, 0.5,  -0.139, 0.967, -0.215, 0.7,
        0.487, 0.255, 0.835,  -1.4, 0.0,    0.0,   0.0,    1.0};

namespace open3d {
namespace t {
namespace pipelines {
namespace registration {

static std::tuple<geometry::PointCloud, geometry::PointCloud>
LoadTensorPointCloudFromFile(const std::string& source_pointcloud_filename,
                             const std::string& target_pointcloud_filename,
                             const double voxel_downsample_factor,
                             const core::Dtype& dtype,
                             const core::Device& device) {
    geometry::PointCloud source, target;

    io::ReadPointCloud(source_pointcloud_filename, source,
                       {"auto", false, false, true});
    io::ReadPointCloud(target_pointcloud_filename, target,
                       {"auto", false, false, true});

    // Eliminates the case of impractical values (including negative).
    if (voxel_downsample_factor > 0.001) {
        // TODO: Use geometry::PointCloud::VoxelDownSample.
        open3d::geometry::PointCloud legacy_s = source.ToLegacy();
        open3d::geometry::PointCloud legacy_t = target.ToLegacy();

        legacy_s = *legacy_s.VoxelDownSample(voxel_downsample_factor);
        legacy_t = *legacy_t.VoxelDownSample(voxel_downsample_factor);

        source = geometry::PointCloud::FromLegacy(legacy_s);
        target = geometry::PointCloud::FromLegacy(legacy_t);
    } else {
        utility::LogWarning(
                " VoxelDownsample: Impractical voxel size [< 0.001], skiping "
                "downsampling.");
    }

    geometry::PointCloud source_device(device), target_device(device);

    core::Tensor source_points = source.GetPointPositions().To(device, dtype);
    source_device.SetPointPositions(source_points);

    core::Tensor target_points = target.GetPointPositions().To(device, dtype);
    core::Tensor target_normals = target.GetPointNormals().To(device, dtype);
    target_device.SetPointPositions(target_points);
    target_device.SetPointNormals(target_normals);

    return std::make_tuple(source_device, target_device);
}

static void BenchmarkRegistrationICP(benchmark::State& state,
                                     const core::Device& device,
                                     const core::Dtype& dtype,
                                     const TransformationEstimationType& type) {
    geometry::PointCloud source(device), target(device);

    std::tie(source, target) = LoadTensorPointCloudFromFile(
            source_pointcloud_filename, target_pointcloud_filename,
            voxel_downsampling_factor, dtype, device);

    std::shared_ptr<TransformationEstimation> estimation;
    if (type == TransformationEstimationType::PointToPlane) {
        estimation = std::make_shared<TransformationEstimationPointToPlane>();
    } else if (type == TransformationEstimationType::PointToPoint) {
        estimation = std::make_shared<TransformationEstimationPointToPoint>();
    }

    core::Tensor init_trans =
            core::Tensor(initial_transform_flat, {4, 4}, core::Float32, device)
                    .To(dtype);

    RegistrationResult reg_result(init_trans);

    // Warm up.
    reg_result = RegistrationICP(
            source, target, max_correspondence_distance, init_trans,
            *estimation,
            ICPConvergenceCriteria(relative_fitness, relative_rmse,
                                   max_iterations));
    for (auto _ : state) {
        reg_result = RegistrationICP(
                source, target, max_correspondence_distance, init_trans,
                *estimation,
                ICPConvergenceCriteria(relative_fitness, relative_rmse,
                                       max_iterations));
        core::cuda::Synchronize(device);
    }

    utility::LogDebug(" PointCloud Size: Source: {}  Target: {}",
                      source.GetPointPositions().GetShape().ToString(),
                      target.GetPointPositions().GetShape().ToString());
    utility::LogDebug(" Max iterations: {}, Max_correspondence_distance : {}",
                      max_iterations, max_correspondence_distance);
}

BENCHMARK_CAPTURE(BenchmarkRegistrationICP,
                  PointToPlane / CPU32,
                  core::Device("CPU:0"),
                  core::Float32,
                  TransformationEstimationType::PointToPlane)
        ->Unit(benchmark::kMillisecond);

#ifdef BUILD_CUDA_MODULE
BENCHMARK_CAPTURE(BenchmarkRegistrationICP,
                  PointToPlane / CUDA32,
                  core::Device("CUDA:0"),
                  core::Float32,
                  TransformationEstimationType::PointToPlane)
        ->Unit(benchmark::kMillisecond);
#endif

BENCHMARK_CAPTURE(BenchmarkRegistrationICP,
                  PointToPoint / CPU32,
                  core::Device("CPU:0"),
                  core::Float32,
                  TransformationEstimationType::PointToPoint)
        ->Unit(benchmark::kMillisecond);

#ifdef BUILD_CUDA_MODULE
BENCHMARK_CAPTURE(BenchmarkRegistrationICP,
                  PointToPoint / CUDA32,
                  core::Device("CUDA:0"),
                  core::Float32,
                  TransformationEstimationType::PointToPoint)
        ->Unit(benchmark::kMillisecond);
#endif

BENCHMARK_CAPTURE(BenchmarkRegistrationICP,
                  PointToPlane / CPU64,
                  core::Device("CPU:0"),
                  core::Float64,
                  TransformationEstimationType::PointToPlane)
        ->Unit(benchmark::kMillisecond);

#ifdef BUILD_CUDA_MODULE
BENCHMARK_CAPTURE(BenchmarkRegistrationICP,
                  PointToPlane / CUDA64,
                  core::Device("CUDA:0"),
                  core::Float64,
                  TransformationEstimationType::PointToPlane)
        ->Unit(benchmark::kMillisecond);
#endif

BENCHMARK_CAPTURE(BenchmarkRegistrationICP,
                  PointToPoint / CPU64,
                  core::Device("CPU:0"),
                  core::Float64,
                  TransformationEstimationType::PointToPoint)
        ->Unit(benchmark::kMillisecond);

#ifdef BUILD_CUDA_MODULE
BENCHMARK_CAPTURE(BenchmarkRegistrationICP,
                  PointToPoint / CUDA64,
                  core::Device("CUDA:0"),
                  core::Float64,
                  TransformationEstimationType::PointToPoint)
        ->Unit(benchmark::kMillisecond);
#endif

}  // namespace registration
}  // namespace pipelines
}  // namespace t
}  // namespace open3d
