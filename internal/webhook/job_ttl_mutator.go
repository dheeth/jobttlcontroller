package webhook

import (
	"context"
	"fmt"

	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
	batchv1 "k8s.io/api/batch/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/prometheus/client_golang/prometheus"
)

// JobTTLMutator patches the TTL seconds after finished for Jobs
type JobTTLMutator struct {
	Client        client.Client
	TargetTTL     int
	LabelSelector string
}

// Metrics
var (
	webhookRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "jobttlcontroller_webhook_requests_total",
			Help: "Total number of webhook admission requests",
		},
		[]string{"operation", "result"},
	)

	webhookJobsPatchedTotal = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "jobttlcontroller_webhook_jobs_patched_total",
			Help: "Total number of Jobs that were patched with TTL values",
		},
	)

	jobsMatchingSelectorTotal = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "jobttlcontroller_jobs_matching_selector_total",
			Help: "Total number of Jobs matching the configured label selector",
		},
	)

	jobsTTLSetTotal = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "jobttlcontroller_jobs_ttl_set_total",
			Help: "Total number of Jobs that had their TTL set",
		},
	)

	jobsTTLAlreadySetTotal = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "jobttlcontroller_jobs_ttl_already_set_total",
			Help: "Total number of Jobs that already had the target TTL value",
		},
	)
)

func init() {
	// Register metrics with the global Prometheus registry
	metrics.Registry.MustRegister(
		webhookRequestsTotal,
		webhookJobsPatchedTotal,
		jobsMatchingSelectorTotal,
		jobsTTLSetTotal,
		jobsTTLAlreadySetTotal,
	)
}

// Default implements admission.CustomDefaulter
func (m *JobTTLMutator) Default(ctx context.Context, obj runtime.Object) error {
	job, ok := obj.(*batchv1.Job)
	if !ok {
		return fmt.Errorf("expected a Job but got a %T", obj)
	}

	logger := log.FromContext(ctx).WithValues("job", job.Name, "namespace", job.Namespace)

	// Increment request counter
	webhookRequestsTotal.WithLabelValues("UPDATE", "allowed").Inc()

	// Check if the job matches the label selector
	if m.LabelSelector != "" {
		selector, err := labels.Parse(m.LabelSelector)
		if err != nil {
			// This should ideally not happen if the selector is validated at startup
			logger.Error(err, "invalid label selector", "selector", m.LabelSelector)
			webhookRequestsTotal.WithLabelValues("UPDATE", "denied").Inc()
			return fmt.Errorf("invalid label selector: %v", err)
		}

		if !selector.Matches(labels.Set(job.Labels)) {
			// No error, just don't default the object
			logger.Info("Job does not match label selector, skipping", "selector", m.LabelSelector, "jobLabels", job.Labels)
			webhookRequestsTotal.WithLabelValues("UPDATE", "skipped").Inc()
			return nil
		}
		logger.Info("Job matches label selector", "selector", m.LabelSelector)
		jobsMatchingSelectorTotal.Inc()
	}

	// If TTL is already set to the target value, do nothing.
	if job.Spec.TTLSecondsAfterFinished != nil && *job.Spec.TTLSecondsAfterFinished == int32(m.TargetTTL) {
		logger.Info("Job already has target TTL value, skipping", "ttlSecondsAfterFinished", *job.Spec.TTLSecondsAfterFinished, "targetTTL", m.TargetTTL)
		jobsTTLAlreadySetTotal.Inc()
		return nil
	}

	// Log the current TTL value if it exists
	if job.Spec.TTLSecondsAfterFinished != nil {
		logger.Info("Job has different TTL value, will update", "currentTTL", *job.Spec.TTLSecondsAfterFinished, "targetTTL", m.TargetTTL)
	} else {
		logger.Info("Job has no TTL value, will set", "targetTTL", m.TargetTTL)
	}

	// Set the TTL
	ttl := int32(m.TargetTTL)
	job.Spec.TTLSecondsAfterFinished = &ttl

	logger.Info("Successfully set TTL for Job", "ttlSecondsAfterFinished", m.TargetTTL)
	webhookJobsPatchedTotal.Inc()
	jobsTTLSetTotal.Inc()

	return nil
}

// SetupWebhookWithManager sets up the webhook with the manager
func (m *JobTTLMutator) SetupWebhookWithManager(mgr ctrl.Manager) error { //nolint:staticcheck
	m.Client = mgr.GetClient()
	return ctrl.NewWebhookManagedBy(mgr).
		For(&batchv1.Job{}).
		WithDefaulter(m).
		Complete()
}
